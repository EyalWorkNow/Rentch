import 'dart:ui';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/search/smart_search.dart' show ScoredProperty;
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
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
          color: const Color(0xFF1E1A18),
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
              child: _statusBadge(p),
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

  Widget _statusBadge(RentalProperty p) {
    final isSale = p.transactionType == PropertyTransactionType.sale;
    final label = isSale ? 'למכירה' : 'להשכרה';
    final dotColor = isSale ? AppColors.coral : const Color(0xFF00FF66);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
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
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
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
    final locationText = p.neighborhood.isNotEmpty
        ? '${p.neighborhood}, ${p.city}'
        : p.city;
    final floorText = p.floor.isNotEmpty ? 'קומה ${p.floor}' : 'קומה 0';

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
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
              const SizedBox(height: 14),
              // Lower Row: 3 Glass Info Pills
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _glassPill(
                      icon: IconsaxPlusLinear.home,
                      label: '${p.roomsLabel} חדרים',
                    ),
                    const SizedBox(width: 8),
                    _glassPill(
                      icon: IconsaxPlusLinear.maximize_3,
                      label: '${p.sizeM2} מ״ר',
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
                          label: 'למה דווקא זו?',
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
            color: Color(0xFF0E1720),
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
                      color: Color(0xFF7CE0E6), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'למה אתי בחרה בדירה הזו',
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

  Widget _pill(
      {required IconData icon, required String label, bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent
            ? const Color(0xFF7CE0E6).withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent
              ? const Color(0xFF7CE0E6).withValues(alpha: 0.5)
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
