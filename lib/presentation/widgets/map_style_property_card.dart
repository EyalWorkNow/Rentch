import 'dart:ui';
import 'package:dating_app/core/ui/platform_fx.dart';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/search/smart_search.dart' show ScoredProperty;
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:dating_app/presentation/widgets/why_details.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// A property card that matches the map / discover page's apartment tile
/// (full‑image, glass pills, price/address overlay) — reused for the listings
/// אתי suggests — PLUS an expandable "why I picked this for you" section built
/// from the match fit % and reasons.
class MapStylePropertyCard extends StatefulWidget {
  const MapStylePropertyCard({
    super.key,
    required this.scored,
    this.onTap,
    this.imageHeight = 190,
  });

  final ScoredProperty scored;
  final VoidCallback? onTap;
  final double imageHeight;

  @override
  State<MapStylePropertyCard> createState() => _MapStylePropertyCardState();
}

class _MapStylePropertyCardState extends State<MapStylePropertyCard> {
  @override
  Widget build(BuildContext context) {
    final p = widget.scored.property;
    final tags = widget.scored.tags;
    // recommendForTenant packs tags as ['NN% התאמה', ...highlights].
    final String? fit = tags.isNotEmpty ? tags.first : null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: widget.onTap,
            child: SizedBox(
              height: widget.imageHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SafeMedia(
                    media: p.primaryMedia,
                    fit: BoxFit.cover,
                    fallback: Container(
                      color: AppColors.navy,
                      child: const Center(
                        child: Icon(IconsaxPlusLinear.building,
                            color: Colors.white30, size: 40)),
                    ),
                  ),
                  // readability gradient
                  const Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 130,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Color(0xD9000000),
                              Color(0x80000000),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // top glass pills — rooms + size
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _glassPill(IconsaxPlusLinear.building, '${p.roomsLabel} חד׳'),
                        if (p.sizeM2 > 0)
                          _glassPill(IconsaxPlusLinear.maximize_3, '${p.sizeM2} מ״ר'),
                        if (fit != null) _glassPill(IconsaxPlusLinear.magic_star, fit),
                      ],
                    ),
                  ),
                  // bottom price + address
                  Positioned(
                    bottom: 12,
                    left: 12,
                    right: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(p.priceLabel,
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: Colors.white)),
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(IconsaxPlusLinear.location,
                              size: 11, color: Colors.white70),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(p.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: WhyDetails(scored: widget.scored),
          ),
        ],
      ),
    );
  }

  Widget _glassPill(IconData icon, String label) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: PlatformFx.blurSigma(8), sigmaY: PlatformFx.blurSigma(8)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white, size: 12),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }

}
