import 'dart:math' as math;

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final tenant = provider.tenantProfile;
        final leads = provider.ownerLeads;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: AppColors.background,
            title: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: AppColors.navy,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    IconsaxPlusBold.home,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'סוויפים למועמדים',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          body: provider.isLoading || tenant == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : SafeArea(
                  child: Column(
                    children: [
                      _OwnerHeader(leadsCount: leads.length),
                      const SizedBox(height: 12),
                      Expanded(
                        child: leads.isEmpty
                            ? const _EmptyOwnerQueue()
                            : CardSwiper(
                                key: ValueKey(
                                  leads.map((p) => p.id).join('-'),
                                ),
                                controller: provider.ownerSwiperController,
                                cardsCount: leads.length,
                                padding:
                                    const EdgeInsets.fromLTRB(10, 0, 10, 0),
                                scale: 0.92,
                                threshold: 35,
                                maxAngle: 16,
                                isLoop: false,
                                numberOfCardsDisplayed:
                                    math.min(2, leads.length),
                                allowedSwipeDirection:
                                    const AllowedSwipeDirection.only(
                                  left: true,
                                  right: true,
                                ),
                                onSwipe: provider.handleOwnerSwipe,
                                cardBuilder: (
                                  context,
                                  index,
                                  horizontalOffsetPercentage,
                                  verticalOffsetPercentage,
                                ) {
                                  return _OwnerLeadCard(
                                    tenant: tenant,
                                    property: leads[index],
                                    tenantReviews: provider.tenantReviews,
                                    horizontalOffsetPercentage:
                                        horizontalOffsetPercentage,
                                  );
                                },
                              ),
                      ),
                      if (leads.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(32, 8, 32, 18),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _OwnerActionBtn(
                                icon: IconsaxPlusBold.close_circle,
                                label: 'דחיה',
                                color: AppColors.coral,
                                size: 62,
                                onPressed: provider.ownerSwipeLeft,
                              ),
                              _OwnerActionBtn(
                                icon: IconsaxPlusBold.heart,
                                label: 'אישור',
                                color: AppColors.primary,
                                size: 72,
                                onPressed: provider.ownerSwipeRight,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _OwnerHeader extends StatelessWidget {
  const _OwnerHeader({required this.leadsCount});
  final int leadsCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2ECF1), width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x06072946),
              blurRadius: 18,
              offset: Offset(0, 8),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(IconsaxPlusBold.profile_2user,
                  color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'תור המועמדים שלך',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: AppColors.navy),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    leadsCount == 0
                        ? 'אין כרגע מועמדים שמחכים להחלטה'
                        : '$leadsCount שוכרים כבר אהבו נכסים ומחכים לסוויפ',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: leadsCount > 0
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.borderLight.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$leadsCount',
                style: TextStyle(
                  color: leadsCount > 0 ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnerLeadCard extends StatelessWidget {
  const _OwnerLeadCard({
    required this.tenant,
    required this.property,
    required this.tenantReviews,
    required this.horizontalOffsetPercentage,
  });

  final TenantProfile tenant;
  final RentalProperty property;
  final List<AppReview> tenantReviews;
  final int horizontalOffsetPercentage;

  @override
  Widget build(BuildContext context) {
    final isAccepting = horizontalOffsetPercentage > 10;
    final isRejecting = horizontalOffsetPercentage < -10;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0xFFE2ECF1), width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C072946),
              blurRadius: 24,
              offset: Offset(0, 12),
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30.8),
          child: Stack(
            children: [
              Column(
                children: [
                  // Photo header
                  Expanded(
                    flex: 5,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        tenant.photoUrl.isEmpty
                            ? Container(
                                color: AppColors.navy,
                                child: const Center(
                                  child: Icon(
                                    IconsaxPlusBold.profile_circle,
                                    size: 72,
                                    color: Colors.white30,
                                  ),
                                ),
                              )
                            : Image.network(
                                tenant.photoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: AppColors.navy,
                                  child: const Center(
                                    child: Icon(
                                      IconsaxPlusBold.profile_circle,
                                      size: 72,
                                      color: Colors.white30,
                                    ),
                                  ),
                                ),
                              ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Color(0xEE072946),
                                Colors.transparent,
                              ],
                              stops: [0.0, 0.65],
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 20,
                          right: 20,
                          left: 20,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tenant.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _TenantChip('תקציב ${_fmt(tenant.budgetMax)}'),
                                  const SizedBox(width: 6),
                                  _TenantChip('${tenant.desiredRooms} חדרים'),
                                  const SizedBox(width: 6),
                                  _TenantChip(tenant.moveInWindow),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Details
                  Expanded(
                    flex: 6,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Liked property
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: AppColors.primary.withValues(alpha: 0.22),
                                  width: 1),
                            ),
                            child: Row(
                              children: [
                                const Icon(IconsaxPlusBold.heart,
                                    size: 15, color: AppColors.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'אהב/ה את ${property.address}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          // Bio
                          Expanded(
                            child: Text(
                              tenant.bio,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                height: 1.5,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          // Reviews
                          if (tenantReviews.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _ReviewRow(review: tenantReviews.first),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // Swipe label
              if (isAccepting || isRejecting)
                Positioned(
                  top: 24,
                  right: isAccepting ? 20 : null,
                  left: isRejecting ? 20 : null,
                  child: Transform.rotate(
                    angle: isAccepting ? -0.15 : 0.15,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isAccepting
                              ? AppColors.primary
                              : AppColors.coral,
                          width: 3.5,
                        ),
                        color: (isAccepting ? AppColors.primary : AppColors.coral)
                            .withValues(alpha: 0.08),
                      ),
                      child: Text(
                        isAccepting ? '✓ מאשר' : '✕ דוחה',
                        style: TextStyle(
                          color:
                              isAccepting ? AppColors.primary : AppColors.coral,
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

class _TenantChip extends StatelessWidget {
  const _TenantChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 10.5,
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.review});
  final AppReview review;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFBEFD8), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                children: List.generate(
                  review.rating,
                  (index) => const Icon(
                    IconsaxPlusBold.star_1,
                    color: Color(0xFFE8A84A),
                    size: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                review.authorName,
                style: const TextStyle(
                  fontWeight: FontWeight.w850,
                  fontSize: 12.5,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            review.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnerActionBtn extends StatelessWidget {
  const _OwnerActionBtn({
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
              border: Border.all(color: color.withValues(alpha: 0.15), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                icon,
                color: color,
                size: size * 0.44,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _EmptyOwnerQueue extends StatelessWidget {
  const _EmptyOwnerQueue();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                IconsaxPlusBold.profile_2user,
                color: AppColors.primary,
                size: 40,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'אין כרגע מועמדים',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navy),
            ),
            const SizedBox(height: 8),
            const Text(
              'כדי לראות מועמדים — אהוב/י דירה במסך הדירות ואז חזור/י לכאן.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.5, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

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
