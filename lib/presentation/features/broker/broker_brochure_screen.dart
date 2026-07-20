import 'dart:io';
import 'dart:ui' as ui;

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/broker_design_models.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/widgets/property_share_sheet.dart';
import 'package:dating_app/presentation/widgets/safe_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

/// ברושור נכס ממותג — the broker (מתווך) picks a listing and gets a polished,
/// WhatsApp-ready one-pager: hero photo, address, price, key facts/features and
/// the agent's branding (logo + brand colours from [BrokerBrandingConfig], name
/// from the broker's own profile). "שתף ברושור" reuses the app's existing
/// property share sheet so the handout goes out as clean text + the listing.
class BrokerBrochureScreen extends StatefulWidget {
  const BrokerBrochureScreen({super.key});

  @override
  State<BrokerBrochureScreen> createState() => _BrokerBrochureScreenState();
}

class _BrokerBrochureScreenState extends State<BrokerBrochureScreen> {
  String? _selectedId;
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  /// Capture the ON-SCREEN branded card as a PNG and share THAT (with the
  /// listing text) — so the "ממותג" one-pager actually reaches the client, not
  /// the generic text share. Falls back to the text sheet on any capture error.
  Future<void> _shareBrochure(RentalProperty property) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _cardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) showPropertyShareSheet(context, property);
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        if (mounted) showPropertyShareSheet(context, property);
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/brochure_${property.id}.png');
      await file.writeAsBytes(data.buffer.asUint8List());
      final text =
          '${property.address}\n${property.priceLabel} ${property.priceSuffixLabel}';
      await Share.shareXFiles([XFile(file.path)], text: text);
    } catch (_) {
      if (mounted) showPropertyShareSheet(context, property); // graceful fallback
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DatingProvider>();
    final properties = provider.myProperties;
    final branding = provider.brokerBranding;
    final agentName = provider.tenantProfile?.name.trim() ?? '';
    final selected = _resolveSelected(properties);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.cloud,
        appBar: AppBar(
          title: const Text('ברושור נכס ממותג'),
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
                      _ChooserStrip(
                        properties: properties,
                        selectedId: selected?.id,
                        onSelect: (id) => setState(() => _selectedId = id),
                      ),
                      if (selected != null) ...[
                        const SizedBox(height: 20),
                        // RepaintBoundary so the branded card can be captured to
                        // an image and shared as the actual one-pager.
                        RepaintBoundary(
                          key: _cardKey,
                          child: _BrochureCard(
                            property: selected,
                            branding: branding,
                            agentName: agentName,
                          ),
                        ),
                        const SizedBox(height: 22),
                        _ShareButton(
                          color: branding.primaryColor,
                          busy: _sharing,
                          onTap: () => _shareBrochure(selected),
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
}

class _ChooserStrip extends StatelessWidget {
  _ChooserStrip({
    required this.properties,
    required this.selectedId,
    required this.onSelect,
  });

  final List<RentalProperty> properties;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (properties.length == 1) return const SizedBox.shrink();
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: properties.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final property = properties[index];
          final selected = property.id == selectedId;
          return GestureDetector(
            onTap: () => onSelect(property.id),
            child: Container(
              width: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.borderLight,
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
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
          );
        },
      ),
    );
  }
}

/// The branded one-pager itself. Pure presentation over real listing data plus
/// the agent's branding; no fabricated facts.
class _BrochureCard extends StatelessWidget {
  const _BrochureCard({
    required this.property,
    required this.branding,
    required this.agentName,
  });

  final RentalProperty property;
  final BrokerBrandingConfig branding;
  final String agentName;

  @override
  Widget build(BuildContext context) {
    final accent = branding.primaryColor;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Hero(property: property, accent: accent),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  property.address,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      property.priceLabel,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        property.priceSuffixLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Facts(property: property, accent: accent),
                if (property.features.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final feature in property.features.take(6))
                        _FeaturePill(label: feature, accent: accent),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                Divider(color: AppColors.borderLight, height: 1),
                const SizedBox(height: 16),
                _BrandFooter(branding: branding, agentName: agentName),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.property, required this.accent});

  final RentalProperty property;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SafeImage(
            source: property.imageUrl,
            fallback: Container(
              color: accent.withValues(alpha: 0.14),
              child: Icon(
                IconsaxPlusLinear.gallery,
                color: accent,
                size: 48,
              ),
            ),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                property.transactionLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.property, required this.accent});

  final RentalProperty property;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final facts = <_Fact>[
      _Fact(IconsaxPlusLinear.home_2, '${property.roomsLabel} חדרים'),
      _Fact(IconsaxPlusLinear.maximize, '${property.sizeM2} מ"ר'),
      if (property.floor.trim().isNotEmpty)
        _Fact(IconsaxPlusLinear.building_4, 'קומה ${property.floor}'),
      if (property.propertyType.trim().isNotEmpty)
        _Fact(IconsaxPlusLinear.buildings, property.propertyType),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final fact in facts)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.cloud,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(fact.icon, size: 18, color: accent),
                const SizedBox(width: 6),
                Text(
                  fact.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
  }
}

class _BrandFooter extends StatelessWidget {
  const _BrandFooter({required this.branding, required this.agentName});

  final BrokerBrandingConfig branding;
  final String agentName;

  @override
  Widget build(BuildContext context) {
    final accent = branding.primaryColor;
    final name = agentName.isEmpty ? 'המתווך שלך' : agentName;
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: branding.hasLogo
              ? SafeImage(
                  source: branding.logoPath,
                  fallback: Icon(IconsaxPlusLinear.user, color: accent),
                )
              : Icon(IconsaxPlusLinear.user, color: accent, size: 26),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'תיווך נדל"ן',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            IconsaxPlusBold.call,
            color: Colors.white,
            size: 22,
          ),
        ),
      ],
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton(
      {required this.color, required this.onTap, this.busy = false});

  final Color color;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: FilledButton.icon(
        onPressed: busy ? null : onTap,
        icon: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Colors.white))
            : const Icon(IconsaxPlusBold.send_2, size: 24),
        label: Text(
          busy ? 'מכין ברושור…' : 'שתף ברושור',
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              IconsaxPlusLinear.gallery,
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
              'הוסיפו נכס כדי להפיק ברושור ממותג לשיתוף.',
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

class _Fact {
  const _Fact(this.icon, this.label);

  final IconData icon;
  final String label;
}
