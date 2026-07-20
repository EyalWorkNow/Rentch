import 'dart:io';
import 'dart:ui' as ui;

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/widgets/safe_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// דוח פעילות לבעל הנכס — the broker (מתווך) picks one of their listings and
/// gets an honest activity summary they can SEND to the property owner, so the
/// owner stays informed and re-lists with them. Every metric comes from real
/// signals on the listing ([RentalProperty.marketSignals]); a missing metric
/// shows "—" rather than a fabricated number.
class BrokerOwnerReportScreen extends StatefulWidget {
  const BrokerOwnerReportScreen({super.key});

  @override
  State<BrokerOwnerReportScreen> createState() =>
      _BrokerOwnerReportScreenState();
}

class _BrokerOwnerReportScreenState extends State<BrokerOwnerReportScreen> {
  String? _selectedId;
  final GlobalKey _reportKey = GlobalKey();
  bool _capturing = false;

  /// Capture the on-screen report as a PNG and share it — a clean image the
  /// owner can save/forward, alongside the existing text-share options. Falls
  /// back silently to the text sheet on any capture error.
  Future<void> _shareAsImage(BuildContext context, RentalProperty p) async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final boundary = _reportKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      final image = await boundary?.toImage(pixelRatio: 3.0);
      final data = await image?.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        if (mounted) _sendToOwner(context, p);
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/report_${p.id}.png');
      await file.writeAsBytes(data.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)],
          text: 'דוח פעילות — ${p.address}');
    } catch (_) {
      if (mounted) _sendToOwner(context, p);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final properties = context.watch<DatingProvider>().myProperties;
    final selected = _resolveSelected(properties);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.cloud,
        appBar: AppBar(
          title: const Text('דוח פעילות לבעל הנכס'),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(color: AppColors.divider, height: 1, thickness: 1),
          ),
        ),
        body: properties.isEmpty
            ? const _EmptyState()
            : SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionLabel('בחרו נכס'),
                      const SizedBox(height: 10),
                      _PropertyPicker(
                        properties: properties,
                        selectedId: selected?.id,
                        onSelect: (id) => setState(() => _selectedId = id),
                      ),
                      if (selected != null) ...[
                        const SizedBox(height: 24),
                        // The report content, wrapped so it can be captured to an
                        // image and shared as a clean one-pager.
                        RepaintBoundary(
                          key: _reportKey,
                          child: Container(
                            color: AppColors.cloud,
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _SectionLabel('סיכום פעילות · ${selected.address}'),
                                const SizedBox(height: 10),
                                _MetricsGrid(property: selected),
                                const SizedBox(height: 20),
                                _SectionLabel('מה לשלוח לבעל הנכס'),
                                const SizedBox(height: 10),
                                _NarrativeCard(text: _narrative(selected)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: _SendButton(
                                onTap: () => _sendToOwner(context, selected),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _ImageShareButton(
                              busy: _capturing,
                              onTap: () => _shareAsImage(context, selected),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  RentalProperty? _resolveSelected(List<RentalProperty> properties) {
    if (properties.isEmpty) return null;
    final match = properties.where((p) => p.id == _selectedId);
    if (match.isNotEmpty) return match.first;
    return properties.first;
  }

  Future<void> _sendToOwner(
    BuildContext context,
    RentalProperty property,
  ) async {
    final report = _reportText(property);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _SendSheet(report: report),
    );
  }
}

/// Maps the listing's real engagement counters into ordered, labelled rows.
/// Honest about provenance: only fields the listing actually exposes are shown
/// as numbers; anything unmeasured falls back to "—".
List<_Metric> _metricsFor(RentalProperty property) {
  final s = property.marketSignals;
  String n(int value) => value > 0 ? _formatNumber(value) : '—';
  return [
    _Metric('צפיות', n(s.views), IconsaxPlusLinear.eye),
    _Metric('מתעניינים (לייקים)', n(s.likes), IconsaxPlusLinear.heart),
    _Metric('שמירות', n(s.saves), IconsaxPlusLinear.archive),
    _Metric('פניות ליצירת קשר', n(s.contactRequests), IconsaxPlusLinear.call),
    _Metric('כניסות לעמוד הנכס', n(s.detailViews), IconsaxPlusLinear.document),
    _Metric(
      'צפייה אחרונה',
      s.lastViewedAt == null ? '—' : _relativeDate(s.lastViewedAt!),
      IconsaxPlusLinear.clock,
    ),
  ];
}

String _narrative(RentalProperty property) {
  final s = property.marketSignals;
  final parts = <String>[];
  if (s.views > 0) {
    parts.add('הנכס נצפה ${_formatNumber(s.views)} פעמים');
  }
  if (s.likes > 0) {
    parts.add('${_formatNumber(s.likes)} מתעניינים סימנו אותו');
  }
  if (s.saves > 0) {
    parts.add('${_formatNumber(s.saves)} שמרו אותו לעיון חוזר');
  }
  if (s.contactRequests > 0) {
    parts.add('התקבלו ${_formatNumber(s.contactRequests)} פניות ליצירת קשר');
  }

  if (parts.isEmpty) {
    return 'הנכס פורסם ופעיל במערכת. בשלב זה טרם נרשמה פעילות מדידה — '
        'נמשיך לעקוב ונעדכן אותך בהמשך.';
  }

  final summary = parts.join(', ');
  return 'עדכון על "${property.address}": $summary. אנחנו ממשיכים לקדם '
      'את הנכס ונשמח לעדכן בכל התקדמות.';
}

String _reportText(RentalProperty property) {
  final lines = <String>[
    'דוח פעילות — ${property.address}',
    '${property.priceLabel} ${property.priceSuffixLabel} · '
        '${property.roomsLabel} חדרים · ${property.sizeM2} מ"ר',
    '',
  ];
  for (final metric in _metricsFor(property)) {
    lines.add('${metric.label}: ${metric.value}');
  }
  lines
    ..add('')
    ..add(_narrative(property));
  if (property.url.trim().isNotEmpty) {
    lines
      ..add('')
      ..add(property.url.trim());
  }
  return lines.join('\n');
}

class _PropertyPicker extends StatelessWidget {
  const _PropertyPicker({
    required this.properties,
    required this.selectedId,
    required this.onSelect,
  });

  final List<RentalProperty> properties;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final property in properties)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PropertyTile(
              property: property,
              selected: property.id == selectedId,
              onTap: () => onSelect(property.id),
            ),
          ),
      ],
    );
  }
}

class _PropertyTile extends StatelessWidget {
  const _PropertyTile({
    required this.property,
    required this.selected,
    required this.onTap,
  });

  final RentalProperty property;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : AppColors.borderLight,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: SafeImage(
                    source: property.imageUrl,
                    fallback: Container(
                      color: AppColors.primaryLight2,
                      child: Icon(
                        IconsaxPlusLinear.gallery,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${property.priceLabel} · ${property.roomsLabel} חדרים',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? IconsaxPlusBold.tick_circle
                    : IconsaxPlusLinear.record,
                color: selected ? AppColors.primary : AppColors.textDisabled,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.property});

  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    final metrics = _metricsFor(property);
    final width = (MediaQuery.sizeOf(context).width - 36 - 12) / 2;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final metric in metrics)
          SizedBox(
            width: width,
            child: _MetricCard(metric: metric),
          ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(metric.icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(height: 14),
          Text(
            metric.value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            metric.label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _NarrativeCard extends StatelessWidget {
  const _NarrativeCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.navy,
          height: 1.6,
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: const Icon(IconsaxPlusBold.send_2, size: 24),
        label: const Text(
          'שלח כטקסט',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}

/// Square button that shares the report as a captured image.
class _ImageShareButton extends StatelessWidget {
  const _ImageShareButton({required this.onTap, this.busy = false});

  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      width: 60,
      child: FilledButton(
        onPressed: busy ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
          foregroundColor: AppColors.primary,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4))
            : const Icon(IconsaxPlusBold.gallery_export, size: 26),
      ),
    );
  }
}

class _SendSheet extends StatelessWidget {
  const _SendSheet({required this.report});

  final String report;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const Text(
                'שליחת הדוח',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 14),
              _SheetAction(
                icon: IconsaxPlusLinear.message_text,
                label: 'שליחה ב-WhatsApp',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _shareVia(
                    context,
                    Uri.parse(
                      'https://wa.me/?text=${Uri.encodeComponent(report)}',
                    ),
                    'לא ניתן לפתוח את WhatsApp כרגע',
                  );
                },
              ),
              const SizedBox(height: 10),
              _SheetAction(
                icon: IconsaxPlusLinear.sms,
                label: 'שליחה ב-SMS',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _shareVia(
                    context,
                    Uri(
                      scheme: 'sms',
                      queryParameters: <String, String>{'body': report},
                    ),
                    'לא ניתן לפתוח SMS כרגע',
                  );
                },
              ),
              const SizedBox(height: 10),
              _SheetAction(
                icon: IconsaxPlusLinear.copy,
                label: 'העתקת הדוח',
                onTap: () async {
                  Navigator.of(context).pop();
                  await Clipboard.setData(ClipboardData(text: report));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('הדוח הועתק')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _shareVia(
  BuildContext context,
  Uri uri,
  String errorMessage,
) async {
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return;
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(errorMessage)));
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cloud,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 24),
              const SizedBox(width: 14),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w900,
        color: AppColors.textSecondary,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              IconsaxPlusLinear.building_4,
              size: 64,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 16),
            const Text(
              'אין עדיין נכסים',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'הוסיפו נכס כדי להפיק דוח פעילות לבעל הנכס.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}

String _formatNumber(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${value < 0 ? '-' : ''}$buffer';
}

String _relativeDate(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 60) return 'לפני פחות משעה';
  if (diff.inHours < 24) return 'לפני ${diff.inHours} שעות';
  if (diff.inDays == 1) return 'אתמול';
  if (diff.inDays < 30) return 'לפני ${diff.inDays} ימים';
  return '${when.day}.${when.month}.${when.year}';
}
