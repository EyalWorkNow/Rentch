import 'dart:io';
import 'dart:ui' as ui;

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/widgets/safe_image.dart';
import 'package:flutter/foundation.dart' show listEquals;
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
      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)],
          text: AppLocalizations.of(context)!
              .brokerOwnerReportScreen9e2251dc(p.address));
    } catch (_) {
      if (mounted) _sendToOwner(context, p);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // `myProperties` recomputes a fresh List<RentalProperty> on every access
    // (a `.where(...).toList()`), so a plain `context.select` would never
    // dedupe (two distinct list instances are never `==`). Selector's
    // `shouldRebuild` lets us do a real element-wise comparison instead, so
    // this screen only rebuilds when the landlord's own listings actually
    // change (add/remove/edit) rather than on every unrelated
    // notifyListeners() elsewhere in DatingProvider (chat, swipes, etc).
    return Selector<DatingProvider, List<RentalProperty>>(
      selector: (_, p) => p.myProperties,
      shouldRebuild: (previous, next) => !listEquals(previous, next),
      builder: (context, properties, _) => _buildContent(context, properties),
    );
  }

  Widget _buildContent(BuildContext context, List<RentalProperty> properties) {
    final selected = _resolveSelected(properties);
    final l10n = AppLocalizations.of(context)!;

    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: AppColors.cloud,
        appBar: AppBar(
          title: Text(l10n.brokerOwnerReportScreen4af427f3),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(color: AppColors.divider, height: 1, thickness: 1),
          ),
        ),
        body: properties.isEmpty
            ? _EmptyState()
            : SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionLabel(l10n.brokerOwnerReportScreen5a6b6baa),
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
                                _SectionLabel(
                                    l10n.brokerOwnerReportScreen80dfca38(
                                        selected.address)),
                                const SizedBox(height: 10),
                                _MetricsGrid(property: selected),
                                const SizedBox(height: 20),
                                _SectionLabel(
                                    l10n.brokerOwnerReportScreenD304ce53),
                                const SizedBox(height: 10),
                                _NarrativeCard(
                                    text: _narrative(context, selected)),
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
    final report = _reportText(context, property);
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
List<_Metric> _metricsFor(BuildContext context, RentalProperty property) {
  final l10n = AppLocalizations.of(context)!;
  final s = property.marketSignals;
  String n(int value) => value > 0 ? _formatNumber(value) : '—';
  return [
    _Metric(l10n.brokerOwnerReportScreen48227f9c, n(s.views),
        IconsaxPlusLinear.eye),
    _Metric(l10n.brokerOwnerReportScreenDaa11b47, n(s.likes),
        IconsaxPlusLinear.heart),
    _Metric(l10n.brokerOwnerReportScreen066de4f8, n(s.saves),
        IconsaxPlusLinear.archive),
    _Metric(l10n.brokerOwnerReportScreenD535641c, n(s.contactRequests),
        IconsaxPlusLinear.call),
    _Metric(l10n.brokerOwnerReportScreenA04be780, n(s.detailViews),
        IconsaxPlusLinear.document),
    _Metric(
      l10n.brokerOwnerReportScreenAc141b12,
      s.lastViewedAt == null ? '—' : _relativeDate(context, s.lastViewedAt!),
      IconsaxPlusLinear.clock,
    ),
  ];
}

String _narrative(BuildContext context, RentalProperty property) {
  final l10n = AppLocalizations.of(context)!;
  final s = property.marketSignals;
  final parts = <String>[];
  if (s.views > 0) {
    parts.add(l10n.brokerOwnerReportScreen564551f8(_formatNumber(s.views)));
  }
  if (s.likes > 0) {
    parts.add(l10n.brokerOwnerReportScreen958d9393(_formatNumber(s.likes)));
  }
  if (s.saves > 0) {
    parts.add(l10n.brokerOwnerReportScreenFa6a4018(_formatNumber(s.saves)));
  }
  if (s.contactRequests > 0) {
    parts.add(
        l10n.brokerOwnerReportScreen825b0fd8(_formatNumber(s.contactRequests)));
  }

  if (parts.isEmpty) {
    return l10n.brokerOwnerReportScreenDf3d7596 +
        l10n.brokerOwnerReportScreen9463334d;
  }

  final summary = parts.join(', ');
  return l10n.brokerOwnerReportScreenF0cf8eae(property.address, summary) +
      l10n.brokerOwnerReportScreen85a17b3a;
}

String _reportText(BuildContext context, RentalProperty property) {
  final l10n = AppLocalizations.of(context)!;
  final lines = <String>[
    l10n.brokerOwnerReportScreenE707f57e(property.address),
    '${property.priceLabel} ${property.priceSuffixLabel} · '
        '${l10n.brokerOwnerReportScreenDb69622a(property.roomsLabel, property.sizeM2)}',
    '',
  ];
  for (final metric in _metricsFor(context, property)) {
    lines.add('${metric.label}: ${metric.value}');
  }
  lines
    ..add('')
    ..add(_narrative(context, property));
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
  _PropertyTile({
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
              color: selected ? AppColors.primary : AppColors.borderLight,
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
                      '${property.priceLabel} · '
                      '${AppLocalizations.of(context)!.brokerOwnerReportScreenD973da64(property.roomsLabel)}',
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
    final metrics = _metricsFor(context, property);
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
  _MetricCard({required this.metric});

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
  _NarrativeCard({required this.text});

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
  _SendButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: const Icon(IconsaxPlusBold.send_2, size: 24),
        label: Text(
          AppLocalizations.of(context)!.brokerOwnerReportScreenFd67190d,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
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
  _ImageShareButton({required this.onTap, this.busy = false});

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
    final l10n = AppLocalizations.of(context)!;
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
              Text(
                l10n.brokerOwnerReportScreenC87bee7b,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 14),
              _SheetAction(
                icon: IconsaxPlusLinear.message_text,
                label: l10n.brokerOwnerReportScreenDe13d87a,
                onTap: () async {
                  Navigator.of(context).pop();
                  await _shareVia(
                    context,
                    Uri.parse(
                      'https://wa.me/?text=${Uri.encodeComponent(report)}',
                    ),
                    l10n.brokerOwnerReportScreenC23278cd,
                  );
                },
              ),
              const SizedBox(height: 10),
              _SheetAction(
                icon: IconsaxPlusLinear.sms,
                label: l10n.brokerOwnerReportScreen217e3171,
                onTap: () async {
                  Navigator.of(context).pop();
                  await _shareVia(
                    context,
                    Uri(
                      scheme: 'sms',
                      queryParameters: <String, String>{'body': report},
                    ),
                    l10n.brokerOwnerReportScreen12d7a7d4,
                  );
                },
              ),
              const SizedBox(height: 10),
              _SheetAction(
                icon: IconsaxPlusLinear.copy,
                label: l10n.brokerOwnerReportScreenB4a9fdcf,
                onTap: () async {
                  Navigator.of(context).pop();
                  await Clipboard.setData(ClipboardData(text: report));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(l10n.brokerOwnerReportScreen452f9d1a)),
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
  _SheetAction({
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
  _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
            Text(
              l10n.brokerOwnerReportScreenC96fa39c,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.brokerOwnerReportScreen6dc67ee5,
              textAlign: TextAlign.center,
              style: const TextStyle(
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

String _relativeDate(BuildContext context, DateTime when) {
  final l10n = AppLocalizations.of(context)!;
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 60) return l10n.brokerOwnerReportScreenA170171d;
  if (diff.inHours < 24)
    return l10n.brokerOwnerReportScreenC46e717b(diff.inHours);
  if (diff.inDays == 1) return l10n.brokerOwnerReportScreenBe285a01;
  if (diff.inDays < 30)
    return l10n.brokerOwnerReportScreen0cfbdf39(diff.inDays);
  return '${when.day}.${when.month}.${when.year}';
}
