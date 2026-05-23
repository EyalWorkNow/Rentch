import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

class ProfileCard extends StatefulWidget {
  const ProfileCard({
    super.key,
    required this.property,
    this.horizontalOffsetPercentage = 0,
  });

  final RentalProperty property;
  final int horizontalOffsetPercentage;

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard> {
  int _currentImage = 0;

  RentalProperty get p => widget.property;

  void _prevImage() {
    if (_currentImage > 0) setState(() => _currentImage--);
  }

  void _nextImage() {
    if (_currentImage < p.imageUrls.length - 1) {
      setState(() => _currentImage++);
    }
  }

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailScreen(property: p),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DatingProvider>();
    final isLiking = widget.horizontalOffsetPercentage > 10;
    final isPassing = widget.horizontalOffsetPercentage < -10;
    final images = p.imageUrls;
    final hasMultiple = images.length > 1;
    final isSaved = provider.isSaved(p.id);
    final score = provider.matchScore(p);
    final priceCtx = provider.priceContext(p);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background image
            _CardImage(
              imageUrl: images.isNotEmpty ? images[_currentImage] : '',
              city: p.city,
            ),

            // Dark gradient
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Color(0xF0072946),
                    Color(0x44072946),
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.42, 0.72],
                ),
              ),
            ),

            // Image navigation tap zones (upper 55% of card)
            if (hasMultiple)
              Positioned.fill(
                child: Column(
                  children: [
                    Expanded(
                      flex: 55,
                      child: Row(
                        children: [
                          // Left tap → prev
                          Expanded(
                            child: GestureDetector(
                              onTap: _prevImage,
                              behavior: HitTestBehavior.translucent,
                              child: const SizedBox.expand(),
                            ),
                          ),
                          // Right tap → next
                          Expanded(
                            child: GestureDetector(
                              onTap: _nextImage,
                              behavior: HitTestBehavior.translucent,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Expanded(flex: 45, child: SizedBox.shrink()),
                  ],
                ),
              ),

            // Tap bottom area → detail page
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: MediaQuery.sizeOf(context).height * 0.28,
              child: GestureDetector(
                onTap: () => _openDetail(context),
                behavior: HitTestBehavior.translucent,
              ),
            ),

            // Top row: agency badge + image dots + save button
            Positioned(
              top: 16,
              right: 16,
              left: 16,
              child: Row(
                children: [
                  _AgencyBadge(agencyListing: p.agencyListing),
                  const Spacer(),
                  if (hasMultiple) ...[
                    _ImageDots(count: images.length, current: _currentImage),
                    const SizedBox(width: 8),
                  ],
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      provider.toggleSave(p.id);
                    },
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isSaved
                            ? IconsaxPlusBold.bookmark
                            : IconsaxPlusLinear.bookmark,
                        color: isSaved ? AppColors.primary : Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Swipe labels
            if (isLiking || isPassing)
              Positioned(
                top: 28,
                left: isPassing ? 22 : null,
                right: isLiking ? 22 : null,
                child: Transform.rotate(
                  angle: isLiking ? -0.15 : 0.15,
                  child: _SwipeBadge(
                    label: isLiking ? '♥ מתאים' : 'דלג',
                    color: isLiking ? AppColors.primary : AppColors.coral,
                  ),
                ),
              ),

            // Content overlay (bottom)
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (score > 0) ...[
                    _MatchScoreBadge(score: score),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '${p.priceLabel} לחודש',
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.1,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _PriceContextBadge(ctx: priceCtx),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(IconsaxPlusLinear.location,
                          size: 14, color: Colors.white70),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          p.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _StatPill(
                            icon: IconsaxPlusBold.building,
                            label: '${p.roomsLabel} חדרים'),
                        const SizedBox(width: 6),
                        _StatPill(
                            icon: IconsaxPlusBold.maximize_3,
                            label: '${p.sizeM2} מ"ר'),
                        if (p.floor.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _StatPill(
                              icon: IconsaxPlusBold.layer,
                              label: 'קומה ${p.floor}'),
                        ],
                        // Price per m²
                        if (p.sizeM2 > 0) ...[
                          const SizedBox(width: 6),
                          _StatPill(
                            icon: IconsaxPlusBold.moneys,
                            label: '₪${(p.price / p.sizeM2).round()}/מ"ר',
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (p.features.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: p.features.take(3).map((f) {
                        return _FeatureTag(label: f);
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => _openDetail(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'פרטים מלאים',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(IconsaxPlusLinear.arrow_left,
                            size: 12,
                            color: AppColors.primary.withValues(alpha: 0.9)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardImage extends StatelessWidget {
  const _CardImage({required this.imageUrl, required this.city});
  final String imageUrl;
  final String city;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) return _ImageFallback(city: city);
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _ImageFallback(city: city),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.city});
  final String city;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              IconsaxPlusBold.building,
              size: 64,
              color: AppColors.primary.withValues(alpha: 0.5),
            ),
            if (city.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                city,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImageDots extends StatelessWidget {
  const _ImageDots({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(IconsaxPlusBold.gallery, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            '${current + 1}/$count',
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _AgencyBadge extends StatelessWidget {
  const _AgencyBadge({required this.agencyListing});
  final bool agencyListing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            agencyListing
                ? IconsaxPlusBold.verify
                : IconsaxPlusBold.profile_circle,
            color: AppColors.primary,
            size: 13,
          ),
          const SizedBox(width: 5),
          Text(
            agencyListing ? 'תיווך מאומת' : 'בעלים פרטי',
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeBadge extends StatelessWidget {
  const _SwipeBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 3),
        color: color.withValues(alpha: 0.08),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 20, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureTag extends StatelessWidget {
  const _FeatureTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _MatchScoreBadge extends StatelessWidget {
  const _MatchScoreBadge({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 80
        ? const Color(0xFF27AE60)
        : score >= 60
            ? const Color(0xFFE67E22)
            : AppColors.coral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(IconsaxPlusBold.star_1, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            '$score% התאמה',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceContextBadge extends StatelessWidget {
  const _PriceContextBadge({required this.ctx});
  final PriceContext ctx;

  @override
  Widget build(BuildContext context) {
    if (ctx == PriceContext.average) return const SizedBox.shrink();
    final isBelow = ctx == PriceContext.belowAverage;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isBelow ? const Color(0xFF27AE60) : AppColors.coral)
            .withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isBelow ? 'מחיר טוב' : 'מחיר גבוה',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
