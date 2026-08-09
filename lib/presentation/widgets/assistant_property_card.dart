import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/search/nearby_relevance.dart';
import 'package:dating_app/core/search/smart_search.dart' show ScoredProperty;
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/features/search/scorecard_view.dart';
import 'package:dating_app/presentation/widgets/property_share_sheet.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:dating_app/presentation/widgets/scale_bounce.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

/// The clean, Messages/matches-page style apartment card אתי suggests — a white
/// rounded card with the hero media, verified/type badges, save+share actions,
/// address/price, info chips, and the expandable data-grounded "why this one"
/// (ScorecardView). Shared by the chat AND the voice conversation.
class AssistantPropertyCard extends StatelessWidget {
  AssistantPropertyCard({
    super.key,
    required this.scored,
    required this.onTap,
    this.width,
  });

  final ScoredProperty scored;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final p = scored.property;
    final w = width ?? MediaQuery.of(context).size.width * 0.82;
    final saved = context.watch<DatingProvider>().isSaved(p.id);
    return ScaleBounce(
      onTap: onTap,
      scaleDownTo: 0.97,
      child: Container(
        width: w,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.border, width: 1),
          boxShadow: [
            BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(5),
              child: AspectRatio(
                aspectRatio: 1.84,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(fit: StackFit.expand, children: [
                    SafeMedia(
                      media: p.media.any((m) => m.isVideo)
                          ? p.media.firstWhere((m) => m.isVideo)
                          : p.primaryMedia,
                      fallback: Container(
                        color: AppColors.primaryLight2,
                        child: Icon(IconsaxPlusLinear.building,
                            color: AppColors.primary, size: 48),
                      ),
                      fit: BoxFit.cover,
                      videoMode: SafeVideoDisplayMode.playback,
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2)),
                          ],
                        ),
                        child: Text(p.propertyType,
                            style: const TextStyle(
                                color: AppColors.navy,
                                fontWeight: FontWeight.w800,
                                fontSize: 12)),
                      ),
                    ),
                    if (p.isVerifiedListing)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                  offset: Offset(0, 2)),
                            ],
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.verified,
                                size: 13, color: AppColors.success),
                            const SizedBox(width: 3),
                            Text(
                                AppLocalizations.of(context)!
                                    .assistantPropertyCard7de9ac58,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.navy)),
                          ]),
                        ),
                      ),
                    Positioned(
                      bottom: 10,
                      left: 10,
                      child: Row(children: [
                        _circleAction(
                          icon: saved ? Icons.favorite : Icons.favorite_border,
                          color: saved ? AppColors.coral : AppColors.navy,
                          onTap: () =>
                              context.read<DatingProvider>().toggleSave(p.id),
                        ),
                        const SizedBox(width: 8),
                        _circleAction(
                          icon: Icons.ios_share,
                          color: AppColors.navy,
                          onTap: () => showPropertyShareSheet(context, p),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.street.isNotEmpty
                                  ? '${p.street} ${p.streetNumber}'
                                  : p.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.navy),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              p.neighborhood.isNotEmpty
                                  ? '${p.city}, ${p.neighborhood}'
                                  : p.city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(p.priceLabel,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _InfoChip(
                          icon: IconsaxPlusLinear.home,
                          label: AppLocalizations.of(context)!
                              .assistantPropertyCardF0f71ca3(p.roomsLabel)),
                      const SizedBox(width: 8),
                      _InfoChip(
                          icon: IconsaxPlusLinear.maximize_3,
                          label: AppLocalizations.of(context)!
                              .assistantPropertyCard615d28b8(p.sizeM2)),
                      for (final t in scored.tags.where((t) => !_isGeoTag(t))) ...[
                        const SizedBox(width: 8),
                        _InfoChip(label: t),
                      ],
                    ]),
                  ),
                  // "Why here" — the real named places (X מ׳ from park/school/…), as
                  // a WRAP of iconsax tags (not a carousel) so each reads clearly.
                  ..._geoWhy(scored.tags),
                  // Expandable transparency panel — the data-grounded "why this
                  // one", with a relevant-only nearby-places dropdown at the bottom.
                  if (scored.scorecard != null)
                    ScorecardView(
                      card: scored.scorecard!,
                      lat: p.lat,
                      lon: p.lon,
                      city: p.city,
                      nearbyProfile: _nearbyProfile(context),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Nearby-relevance profile from the captured persona (no live query here) —
  // decides which nearby-places sections show in this card's "למה זו" preview.
  NearbyProfile _nearbyProfile(BuildContext context) {
    final tp = context.read<DatingProvider>().tenantProfile;
    final text = '${tp?.bio ?? ''} '
        '${(tp?.importantDetails ?? const <String>[]).join(' ')}';
    return NearbyProfile.fromText(text);
  }

  Widget _circleAction({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Icon(icon, size: 17, color: color),
      ),
    );
  }
}

// Geo "why here" tags are emoji-prefixed in the engine; here we map the emoji to
// an iconsax icon and strip it from the label.
const Map<String, IconData> _geoIcon = {
  '🏫': IconsaxPlusLinear.buildings_2,
  '🌳': IconsaxPlusLinear.tree,
  '🚉': IconsaxPlusLinear.bus,
  '🏖️': IconsaxPlusLinear.sun_1,
  '🎓': IconsaxPlusLinear.teacher,
  '🍸': IconsaxPlusLinear.coffee,
};

bool _isGeoTag(String t) => _geoIcon.keys.any(t.startsWith);

/// Render the geo tags (if any) as a wrap under the quick facts.
List<Widget> _geoWhy(List<String> tags) {
  final geo = tags.where(_isGeoTag).toList();
  if (geo.isEmpty) return const [];
  return [
    Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final t in geo) _GeoTag(t)],
      ),
    ),
  ];
}

class _GeoTag extends StatelessWidget {
  _GeoTag(this.raw);
  final String raw;

  @override
  Widget build(BuildContext context) {
    var icon = IconsaxPlusLinear.location;
    var label = raw;
    for (final e in _geoIcon.entries) {
      if (raw.startsWith(e.key)) {
        icon = e.value;
        label = raw.substring(e.key.length).trim();
        break;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.navy)),
      ]),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({this.icon, required this.label});
  final IconData? icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.slate100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: AppColors.navy),
          const SizedBox(width: 6),
        ],
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.navy)),
      ]),
    );
  }
}
