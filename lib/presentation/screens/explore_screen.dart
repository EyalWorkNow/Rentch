import 'dart:math' as math;

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/add_property_screen.dart';
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
                  'מצב משכיר',
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
                      const SizedBox(height: 10),
                      _LandlordStatsRow(stats: provider.landlordStats),
                      // Add property button — landlord-only, visible in body
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const AddPropertyScreen()),
                            ),
                            icon: const Icon(IconsaxPlusBold.add_square,
                                size: 16),
                            label: const Text('הוסף דירה חדשה'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                      ),
                      if (provider.myProperties.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _MyPropertiesSection(
                            properties: provider.myProperties),
                      ],
                      const SizedBox(height: 8),
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

class _MyPropertiesSection extends StatelessWidget {
  const _MyPropertiesSection({required this.properties});
  final List<RentalProperty> properties;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(IconsaxPlusBold.building,
                  size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text(
                'הדירות שלי',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${properties.length}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: properties.length,
            itemBuilder: (context, i) {
              final p = properties[i];
              final imgUrl =
                  p.imageUrls.isNotEmpty ? p.imageUrls.first : '';
              return Container(
                width: 160,
                margin: const EdgeInsets.only(left: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderLight),
                  boxShadow: const [
                    BoxShadow(
                        color: AppColors.shadow,
                        blurRadius: 8,
                        offset: Offset(0, 3))
                  ],
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(16)),
                      child: SizedBox(
                        width: 60,
                        height: double.infinity,
                        child: imgUrl.isEmpty
                            ? Container(
                                color: AppColors.primaryLight2,
                                child: const Icon(IconsaxPlusBold.building,
                                    color: AppColors.primary, size: 22))
                            : Image.network(imgUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                    color: AppColors.primaryLight2,
                                    child: const Icon(
                                        IconsaxPlusBold.building,
                                        color: AppColors.primary,
                                        size: 22))),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              p.priceLabel,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.primary),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              p.city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.navy,
                                  fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 3),
                            GestureDetector(
                              onTap: () => context
                                  .read<DatingProvider>()
                                  .removeLandlordProperty(p.id),
                              child: const Text(
                                'הסר',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.coral,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: const [
            BoxShadow(color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(IconsaxPlusBold.profile_2user,
                  color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'מועמדים ממתינים',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: AppColors.navy),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    leadsCount == 0
                        ? 'אין כרגע מועמדים'
                        : '$leadsCount שוכרים אהבו את הדירה שלך',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: leadsCount > 0
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.borderLight,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$leadsCount',
                style: TextStyle(
                  color: leadsCount > 0 ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          color: Colors.white,
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
                                Color(0xDD072946),
                                Colors.transparent,
                              ],
                              stops: [0.0, 0.6],
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 16,
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
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  _TenantChip(
                                      'תקציב ${_fmt(tenant.budgetMax)}'),
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
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Liked property
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.25)),
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
                          const SizedBox(height: 12),
                          // Bio
                          Expanded(
                            child: Text(
                              tenant.bio,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                height: 1.5,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          // Reviews
                          if (tenantReviews.isNotEmpty) ...[
                            const SizedBox(height: 10),
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
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isAccepting
                              ? AppColors.primary
                              : AppColors.coral,
                          width: 3,
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
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

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.review});
  final AppReview review;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          const Icon(IconsaxPlusBold.star_1, color: Color(0xFFE8A84A), size: 15),
          const SizedBox(width: 5),
          Text(
            '${review.rating}/5',
            style: const TextStyle(
                fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.navy),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              review.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
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
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.36),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.42),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
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
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandlordStatsRow extends StatelessWidget {
  const _LandlordStatsRow({required this.stats});
  final LandlordStats stats;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _StatCard(
            icon: IconsaxPlusBold.building,
            value: '${stats.propertiesCount}',
            label: 'דירות',
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          _StatCard(
            icon: IconsaxPlusBold.profile_2user,
            value: '${stats.totalCandidatesSeen}',
            label: 'מועמדים',
            color: AppColors.navy,
          ),
          const SizedBox(width: 8),
          _StatCard(
            icon: IconsaxPlusBold.heart,
            value: '${stats.matchesCount}',
            label: 'התאמות',
            color: const Color(0xFF27AE60),
          ),
          const SizedBox(width: 8),
          _StatCard(
            icon: IconsaxPlusBold.timer_1,
            value: '${stats.pendingCount}',
            label: 'ממתינים',
            color: const Color(0xFFE67E22),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: const [
            BoxShadow(
                color: AppColors.shadow, blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(child: Icon(icon, size: 16, color: color)),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
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
