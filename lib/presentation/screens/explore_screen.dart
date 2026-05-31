import 'dart:math' as math;

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/add_property_screen.dart';
import 'package:dating_app/presentation/screens/matches_screen.dart';
import 'package:dating_app/presentation/widgets/safe_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final tenant = provider.tenantProfile;
        final leads = provider.ownerLeads;
        final total = leads.length;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: provider.isLoading || tenant == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : SafeArea(
                  child: Column(
                    children: [
                      _TopBar(
                        current: _currentIndex,
                        total: total,
                        trustScore: provider.trustScore,
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: leads.isEmpty
                            ? const _EmptyOwnerQueue()
                            : CardSwiper(
                                key: ValueKey(
                                    leads.map((p) => p.id).join('-')),
                                controller:
                                    provider.ownerSwiperController,
                                cardsCount: leads.length,
                                padding: const EdgeInsets.fromLTRB(
                                    12, 0, 12, 0),
                                scale: 0.93,
                                threshold: 32,
                                maxAngle: 14,
                                isLoop: false,
                                numberOfCardsDisplayed:
                                    math.min(2, leads.length),
                                allowedSwipeDirection:
                                    const AllowedSwipeDirection.only(
                                  left: true,
                                  right: true,
                                ),
                                onSwipe: (prev, current, dir) {
                                  if (current != null && mounted) {
                                    setState(() =>
                                        _currentIndex = current);
                                  }
                                  return provider.handleOwnerSwipe(
                                      prev, current, dir);
                                },
                                cardBuilder: (
                                  context,
                                  index,
                                  hOffset,
                                  vOffset,
                                ) {
                                  return _LeadCard(
                                    tenant: tenant,
                                    property: leads[index],
                                    reviews: provider.tenantReviews,
                                    hOffset: hOffset,
                                  );
                                },
                              ),
                      ),
                      if (leads.isNotEmpty)
                        _ActionBar(
                          onSkip: () {
                            HapticFeedback.lightImpact();
                            provider.ownerSwiperController
                                .swipe(CardSwiperDirection.bottom);
                          },
                          onReject: () {
                            HapticFeedback.mediumImpact();
                            provider.ownerSwipeLeft();
                          },
                          onAccept: () {
                            HapticFeedback.heavyImpact();
                            provider.ownerSwipeRight();
                          },
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

// ─── Top bar ──────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.current,
    required this.total,
    required this.trustScore,
  });

  final int current;
  final int total;
  final int trustScore;

  @override
  Widget build(BuildContext context) {
    final remaining = math.max(0, total - current);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'מועמדים',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                    height: 1.1,
                  ),
                ),
                if (total > 0)
                  Text(
                    '$remaining ממתינים להחלטה',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  )
                else
                  const Text(
                    'אין כרגע מועמדים חדשים',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (total > 0) ...[
            // Progress dots / pill
            _ProgressPill(current: current, total: total),
            const SizedBox(width: 10),
          ],
          // Trust score badge
          if (trustScore > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _trustColor(trustScore).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(IconsaxPlusBold.shield_tick,
                      size: 13, color: _trustColor(trustScore)),
                  const SizedBox(width: 5),
                  Text(
                    '$trustScore נקודות אמון',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _trustColor(trustScore),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _trustColor(int score) {
    if (score >= 80) return const Color(0xFF27AE60);
    if (score >= 50) return const Color(0xFFE67E22);
    return AppColors.coral;
  }
}

class _ProgressPill extends StatelessWidget {
  const _ProgressPill({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(IconsaxPlusBold.profile_2user,
              size: 12, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(
            '${current + 1}/$total',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Lead Card ────────────────────────────────────────────────────────────────

class _LeadCard extends StatefulWidget {
  const _LeadCard({
    required this.tenant,
    required this.property,
    required this.reviews,
    required this.hOffset,
  });

  final TenantProfile tenant;
  final RentalProperty property;
  final List<AppReview> reviews;
  final int hOffset;

  @override
  State<_LeadCard> createState() => _LeadCardState();
}

class _LeadCardState extends State<_LeadCard> {
  int _photoIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isAccepting = widget.hOffset > 10;
    final isRejecting = widget.hOffset < -10;
    final photos = widget.tenant.photoUrls;
    final hasMultiplePhotos = photos.length > 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12072946),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: Stack(
            children: [
              // Main scrollable content
              Column(
                children: [
                  // ── Photo header ────────────────────────────────────────
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.38,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Photo
                        AnimatedSwitcher(
                          duration:
                              const Duration(milliseconds: 200),
                          child: SafeImage(
                            key: ValueKey(_photoIndex),
                            source: photos.isNotEmpty
                                ? photos[_photoIndex]
                                : '',
                            fallback: Container(
                              color: AppColors.navy,
                              child: const Center(
                                child: Icon(
                                  IconsaxPlusBold.profile_circle,
                                  size: 80,
                                  color: Colors.white24,
                                ),
                              ),
                            ),
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                          ),
                        ),
                        // Bottom gradient
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Color(0xF2072946),
                                Color(0x22072946),
                                Colors.transparent,
                              ],
                              stops: [0.0, 0.5, 0.8],
                            ),
                          ),
                        ),
                        // Photo navigation tap zones
                        if (hasMultiplePhotos)
                          Positioned.fill(
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      if (_photoIndex > 0) {
                                        setState(() => _photoIndex--);
                                      }
                                    },
                                    behavior:
                                        HitTestBehavior.translucent,
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      if (_photoIndex <
                                          photos.length - 1) {
                                        setState(() => _photoIndex++);
                                      }
                                    },
                                    behavior:
                                        HitTestBehavior.translucent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // Photo dots
                        if (hasMultiplePhotos)
                          Positioned(
                            top: 14,
                            left: 0,
                            right: 0,
                            child: _PhotoDots(
                              count: photos.length,
                              current: _photoIndex,
                            ),
                          ),
                        // Name + chips overlay
                        Positioned(
                          bottom: 16,
                          right: 18,
                          left: 18,
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.tenant.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _TenantChip(
                                    icon: IconsaxPlusBold.wallet,
                                    label: _fmt(
                                        widget.tenant.budgetMax),
                                  ),
                                  _TenantChip(
                                    icon: IconsaxPlusBold.building,
                                    label:
                                        '${widget.tenant.desiredRooms.toStringAsFixed(widget.tenant.desiredRooms % 1 == 0 ? 0 : 1)} חדרים',
                                  ),
                                  _TenantChip(
                                    icon: IconsaxPlusBold.calendar,
                                    label:
                                        widget.tenant.moveInWindow,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Scrollable details ──────────────────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Liked property
                          _LikedPropertyBox(
                              property: widget.property),
                          const SizedBox(height: 14),
                          // Key detail cells
                          Row(
                            children: [
                              Expanded(
                                child: _DetailCell(
                                  icon: IconsaxPlusBold.calendar,
                                  label: 'כניסה',
                                  value:
                                      widget.tenant.moveInWindow,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _DetailCell(
                                  icon: IconsaxPlusBold.wallet,
                                  label: 'תקציב',
                                  value: _fmt(
                                      widget.tenant.budgetMax),
                                ),
                              ),
                            ],
                          ),
                          // Important details chips
                          if (widget.tenant.importantDetails
                              .isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: widget.tenant.importantDetails
                                  .take(4)
                                  .map((d) => _DetailTag(d))
                                  .toList(),
                            ),
                          ],
                          // Bio
                          if (widget.tenant.bio.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            const Divider(
                                height: 1,
                                color: Color(0xFFEAF2F7)),
                            const SizedBox(height: 12),
                            Text(
                              widget.tenant.bio,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                                height: 1.6,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          // Reviews
                          if (widget.reviews.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            const Divider(
                                height: 1,
                                color: Color(0xFFEAF2F7)),
                            const SizedBox(height: 12),
                            _ReviewSection(
                                reviews: widget.reviews),
                          ],
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // Swipe overlay badges — RTL-aware positioning
              if (isAccepting || isRejecting)
                Positioned(
                  top: 22,
                  right: isAccepting ? 18 : null,
                  left: isRejecting ? 18 : null,
                  child: Transform.rotate(
                    angle: isAccepting ? -0.13 : 0.13,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isAccepting
                              ? AppColors.primary
                              : AppColors.coral,
                          width: 3,
                        ),
                        color: (isAccepting
                                ? AppColors.primary
                                : AppColors.coral)
                            .withValues(alpha: 0.1),
                      ),
                      child: Text(
                        isAccepting ? '✓ מאשר' : '✕ דוחה',
                        style: TextStyle(
                          color: isAccepting
                              ? AppColors.primary
                              : AppColors.coral,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
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

// ─── Photo dots ───────────────────────────────────────────────────────────────

class _PhotoDots extends StatelessWidget {
  const _PhotoDots({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive
                ? Colors.white
                : Colors.white.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

// ─── Liked property box ───────────────────────────────────────────────────────

class _LikedPropertyBox extends StatelessWidget {
  const _LikedPropertyBox({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.08),
            AppColors.primary.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(IconsaxPlusBold.heart,
                size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'אהב/ה את הנכס',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  property.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              property.priceLabel,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Detail cell ──────────────────────────────────────────────────────────────

class _DetailCell extends StatelessWidget {
  const _DetailCell(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child:
                Icon(icon, size: 14, color: AppColors.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Detail tag chip ──────────────────────────────────────────────────────────

class _DetailTag extends StatelessWidget {
  const _DetailTag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E8F0)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.navy,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─── Tenant chip (on photo) ───────────────────────────────────────────────────

class _TenantChip extends StatelessWidget {
  const _TenantChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.2), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Review section ───────────────────────────────────────────────────────────

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({required this.reviews});
  final List<AppReview> reviews;

  @override
  Widget build(BuildContext context) {
    final r = reviews.first;
    final avg = reviews.fold(0, (s, x) => s + x.rating) /
        reviews.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFBEFD8), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(IconsaxPlusBold.star_1,
                  color: Color(0xFFE8A84A), size: 14),
              const SizedBox(width: 5),
              Text(
                '${avg.toStringAsFixed(1)} מתוך 5',
                style: const TextStyle(
                  color: Color(0xFFB07D1A),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '(${reviews.length} ביקורות)',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _StarRating(rating: r.rating),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '"${r.text}"',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '— ${r.authorName}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StarRating extends StatelessWidget {
  const _StarRating({required this.rating});
  final int rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < rating
              ? IconsaxPlusBold.star_1
              : IconsaxPlusBold.star,
          color: i < rating
              ? const Color(0xFFE8A84A)
              : const Color(0xFFD9C8A0),
          size: 12,
        );
      }),
    );
  }
}

// ─── Action bar ───────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onSkip,
    required this.onReject,
    required this.onAccept,
  });

  final VoidCallback onSkip;
  final VoidCallback onReject;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 10),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ActionBtn(
              icon: IconsaxPlusBold.forward,
              label: 'דלג',
              color: AppColors.textSecondary,
              size: 54,
              onPressed: onSkip,
            ),
            _ActionBtn(
              icon: IconsaxPlusBold.close_circle,
              label: 'דחיה',
              color: AppColors.coral,
              size: 66,
              onPressed: onReject,
            ),
            _ActionBtn(
              icon: IconsaxPlusBold.tick_circle,
              label: 'אישור',
              color: AppColors.primary,
              size: 72,
              onPressed: onAccept,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.size,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                  color: color.withValues(alpha: 0.18), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Icon(icon, color: color, size: size * 0.42),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyOwnerQueue extends StatelessWidget {
  const _EmptyOwnerQueue();

  @override
  Widget build(BuildContext context) {
    final hasProperties =
        context.read<DatingProvider>().myProperties.isNotEmpty;
    final hasMatches = context.read<DatingProvider>().matches.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                IconsaxPlusBold.profile_2user,
                color: AppColors.primary,
                size: 42,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'אין מועמדים חדשים',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasProperties
                  ? 'כאשר שוכרים יאהבו את הנכסים שלך הם יופיעו כאן לאישור.'
                  : 'הוסף נכס ראשון — שוכרים שיאהבו אותו יופיעו כאן.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.6,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 28),
            if (!hasProperties)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const AddPropertyScreen()),
                  ),
                  icon: const Icon(IconsaxPlusBold.add_square, size: 17),
                  label: const Text('הוסף נכס עכשיו'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            if (hasProperties && hasMatches)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MatchesScreen()),
                  ),
                  icon: const Icon(IconsaxPlusBold.message, size: 17),
                  label: const Text('עבור לשיחות'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.navy,
                    side: const BorderSide(color: AppColors.borderLight),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _fmt(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final remaining = raw.length - i;
    buffer.write(raw[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  return '₪$buffer';
}
