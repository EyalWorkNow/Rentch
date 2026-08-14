import 'dart:ui';
import 'package:dating_app/core/ui/platform_fx.dart';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/utils/helpers/property_label_helper.dart';
import 'package:dating_app/core/search/smart_search.dart' show ScoredProperty;
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/features/search/scorecard_view.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:dating_app/presentation/widgets/scale_bounce.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

/// A dedicated, immersive property card for Eti's voice conversation screens.
/// Features full-bleed background media, top glassmorphism status/save badges,
/// and a distinctive bottom dark-glass overlay with price, location, and info chips.
class AtiVoicePropertyCard extends StatelessWidget {
  const AtiVoicePropertyCard({
    super.key,
    required this.scored,
    required this.onTap,
    this.width,
    this.height,
  });

  final ScoredProperty scored;
  final VoidCallback onTap;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final p = scored.property;
    final w = width ?? MediaQuery.of(context).size.width * 0.82;
    final h = height ?? double.infinity;
    final saved = context.watch<DatingProvider>().isSaved(p.id);

    return ScaleBounce(
      onTap: onTap,
      scaleDownTo: 0.97,
      child: Container(
        width: w,
        height: h,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Full card hero image / media
            SafeMedia(
              media: p.media.any((m) => m.isVideo)
                  ? p.media.firstWhere((m) => m.isVideo)
                  : p.primaryMedia,
              fallback: Container(
                color: AppColors.navy,
                child: const Center(
                  child: Icon(IconsaxPlusLinear.building,
                      color: Colors.white30, size: 48),
                ),
              ),
              fit: BoxFit.cover,
              videoMode: SafeVideoDisplayMode.playback,
            ),

            // Top Left Status Badge (e.g., "להשכרה" with green dot)
            Positioned(
              top: 14,
              left: 14,
              child: _statusBadge(context, p),
            ),

            // Top Right Heart / Save Button
            Positioned(
              top: 14,
              right: 14,
              child: _heartButton(context, p, saved),
            ),

            // Bottom Dark Glass Overlay Box
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _bottomOverlay(context, p),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(BuildContext context, RentalProperty p) {
    final isSale = p.transactionType == PropertyTransactionType.sale;
    final l10n = AppLocalizations.of(context)!;
    final label = isSale
        ? l10n.atiVoicePropertyCard609fac18
        : l10n.atiVoicePropertyCardB336259f;
    final dotColor = isSale ? AppColors.coral : const Color(0xFF00FF66);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(14), sigmaY: PlatformFx.blurSigma(14)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heartButton(BuildContext context, RentalProperty p, bool saved) {
    return GestureDetector(
      onTap: () => context.read<DatingProvider>().toggleSave(p.id),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(14), sigmaY: PlatformFx.blurSigma(14)),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.38),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: Icon(
              saved ? Icons.favorite : Icons.favorite_border,
              color: saved ? AppColors.coral : Colors.white,
              size: 21,
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomOverlay(BuildContext context, RentalProperty p) {
    final l10n = AppLocalizations.of(context)!;
    final locationText = p.neighborhood.isNotEmpty
        ? '${p.neighborhood}, ${p.city}'
        : p.city;
    final floorText = p.floor.isNotEmpty
        ? l10n.atiVoicePropertyCard77d9ac8f(floorLabel(p.floor, l10n))
        : l10n.atiVoicePropertyCard5bf47d1e;

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(24), sigmaY: PlatformFx.blurSigma(24)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xD92C2317), // Warm dark brownish-bronze glass
                Color(0xF216120C), // Deep black-brown base
              ],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Upper Row: Price & Location (Right), Arrow Button (Left)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          p.priceLabel,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p.priceSuffixLabel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              IconsaxPlusLinear.location,
                              size: 16,
                              color: Color(0xFFE5B86E), // Warm golden pin
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                locationText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Left arrow navigation circle button
                  GestureDetector(
                    onTap: onTap,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        IconsaxPlusLinear.arrow_left,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              // VISIBLE "why" — so the user sees WHY אתי picked this flat right on
              // the card, not hidden behind a pill they'd have to scroll to. Tap
              // opens the full explainability scorecard.
              if (_whyText() != null) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _showWhy(context),
                  child: _whyRow(context, _whyText()!),
                ),
              ],
              const SizedBox(height: 14),
              // Lower Row: 3 Glass Info Pills
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _glassPill(
                      icon: IconsaxPlusLinear.home,
                      label: l10n.atiVoicePropertyCardF0f71ca3(p.roomsLabel),
                    ),
                    const SizedBox(width: 8),
                    _glassPill(
                      icon: IconsaxPlusLinear.maximize_3,
                      label: l10n.atiVoicePropertyCard615d28b8(p.sizeM2),
                    ),
                    const SizedBox(width: 8),
                    _glassPill(
                      icon: IconsaxPlusLinear.layer,
                      label: floorText,
                    ),
                    if (scored.scorecard != null) ...[
                      const SizedBox(width: 8),
                      // "Why this one?" — opens the same explainability scorecard
                      // אתי shows in the chat, so the reasoning is available in voice too.
                      GestureDetector(
                        onTap: () => _showWhy(context),
                        child: _pill(
                          icon: IconsaxPlusBold.magic_star,
                          label: l10n.atiVoicePropertyCard5e3842ff,
                          accent: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Bottom sheet with אתי's full match reasoning (fit %, matched criteria, notes).
  void _showWhy(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
          child: ListView(
            controller: controller,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(IconsaxPlusBold.magic_star,
                      color: AppColors.tealBright, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!
                          .atiVoicePropertyCardDadd9f97,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ScorecardView(card: scored.scorecard!),
            ],
          ),
        ),
      ),
    );
  }

  // A concise, honest "why" — prefers אתי's warm LLM sentence, then the engine's
  // highlights / persona reasons, then the two top-weighted dimensions. Null when
  // there's no scorecard (nothing truthful to say).
  String? _whyText() {
    final c = scored.scorecard;
    if (c == null) return null;
    String pick() {
      if (c.llmReason != null && c.llmReason!.trim().isNotEmpty) {
        return c.llmReason!.trim();
      }
      if (c.highlights.isNotEmpty) return c.highlights.take(2).join(' · ');
      if (c.personaReasons.isNotEmpty) return c.personaReasons.first;
      // c.dimensions is already ordered stated-first (what the user searched
      // for), so take them as-is — never re-sort to generic high-score axes.
      return c.dimensions.take(2).map((d) => d.label).join(' · ');
    }

    final r = pick().trim();
    return r.isEmpty ? null : r;
  }

  // The visible reason line: ✨ fit% + short "why", tappable for the full card.
  Widget _whyRow(BuildContext context, String why) {
    final fit = scored.scorecard?.fitPct;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.tealBright.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.tealBright.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(IconsaxPlusBold.magic_star,
              size: 15, color: Color(0xFF9BEAF0)),
          const SizedBox(width: 7),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                if (fit != null)
                  TextSpan(
                    text: AppLocalizations.of(context)!
                        .atiVoicePropertyCard74f4db63(fit),
                    style: const TextStyle(
                        color: Color(0xFF9BEAF0), fontWeight: FontWeight.w800),
                  ),
                TextSpan(text: why),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(IconsaxPlusLinear.arrow_left_2,
              size: 14, color: Colors.white54),
        ],
      ),
    );
  }

  Widget _pill(
      {required IconData icon, required String label, bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent
            ? AppColors.tealBright.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent
              ? AppColors.tealBright.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.14),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent ? const Color(0xFF9BEAF0) : Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: accent ? const Color(0xFF9BEAF0) : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
