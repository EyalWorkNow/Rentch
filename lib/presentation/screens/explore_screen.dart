import 'dart:math' as math;
import 'dart:ui';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/add_property_screen.dart';
import 'package:dating_app/presentation/screens/matches_screen.dart';
import 'package:dating_app/presentation/screens/tenant_detail_screen.dart';
import 'package:dating_app/presentation/widgets/safe_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
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

        // Reset index safely if total changes
        final safeIndex = total > 0 ? _currentIndex.clamp(0, total - 1) : 0;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: AppColors.background,
            elevation: 0,
            centerTitle: true,
            title: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEDF1F5),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.black.withOpacity(0.04)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RentlyIcon(
                    IconsaxPlusLinear.profile_2user,
                    size: 15,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'מועמדים',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  if (total > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${safeIndex + 1}/$total',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (total > 0 && provider.trustScore > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _trustColor(provider.trustScore).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RentlyIcon(
                            IconsaxPlusLinear.shield_tick,
                            size: 13,
                            color: _trustColor(provider.trustScore),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${provider.trustScore}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _trustColor(provider.trustScore),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: provider.isLoading || tenant == null
              ? Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      _buildAutoLikeCard(provider),
                      Expanded(
                        child: leads.isEmpty
                            ? const _EmptyOwnerQueue()
                            : Stack(
                                children: [
                                  // Full-height card swiper
                                  Positioned.fill(
                                    child: CardSwiper(
                                      key: ValueKey(leads.map((p) => p.id).join('-')),
                                      controller: provider.ownerSwiperController,
                                      cardsCount: leads.length,
                                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 150),
                                      scale: 0.93,
                                      threshold: 38,
                                      maxAngle: 16,
                                      isLoop: false,
                                      numberOfCardsDisplayed: math.min(3, leads.length),
                                      backCardOffset: const Offset(0, 20),
                                      allowedSwipeDirection: const AllowedSwipeDirection.only(
                                        left: true,
                                        right: true,
                                        up: true,
                                      ),
                                      onSwipe: (prev, current, dir) {
                                        if (current != null && mounted) {
                                          setState(() => _currentIndex = current);
                                        }
                                        return provider.handleOwnerSwipe(prev, current, dir);
                                      },
                                      cardBuilder: (context, index, hOffset, vOffset) {
                                        if (index < 0 || index >= leads.length) {
                                          return const SizedBox.shrink();
                                        }
                                        final lead = leads[index];
                                        return _LeadCard(
                                          tenant: tenant,
                                          property: lead,
                                          reviews: provider.tenantReviews,
                                          hOffset: hOffset,
                                          isHighFit:
                                              provider.isHighFitLead(lead),
                                          fitReason:
                                              provider.leadFitReason(lead),
                                        );
                                      },
                                    ),
                                  ),

                                  // Floating centered action buttons
                                  Positioned(
                                    bottom: 165,
                                    left: 0,
                                    right: 0,
                                    child: _ActionButtons(
                                      onReject: () {
                                        HapticFeedback.mediumImpact();
                                        provider.ownerSwipeLeft();
                                      },
                                      onAccept: () {
                                        HapticFeedback.heavyImpact();
                                        provider.ownerSwipeRight();
                                      },
                                      onInfo: () {
                                        if (leads.isEmpty || safeIndex >= leads.length) return;
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => TenantDetailScreen(
                                              tenant: tenant,
                                              property: leads[safeIndex],
                                              reviews: provider.tenantReviews,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
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

  Widget _buildAutoLikeCard(DatingProvider provider) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 12, 18, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: provider.autoLikeEnabled
              ? [
                  AppColors.primary.withOpacity(0.08),
                  const Color(0xFF13BEC9).withOpacity(0.04),
                ]
              : [
                  Colors.white.withOpacity(0.9),
                  Colors.white.withOpacity(0.95),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: provider.autoLikeEnabled
              ? AppColors.primary.withOpacity(0.3)
              : const Color(0xFFE2E8F0),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: provider.autoLikeEnabled
                ? AppColors.primary.withOpacity(0.08)
                : Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: provider.autoLikeEnabled
                  ? AppColors.primary.withOpacity(0.12)
                  : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              IconsaxPlusBold.flash,
              color: provider.autoLikeEnabled ? AppColors.primary : AppColors.textSecondary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'לייק אוטומטי',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'אישור אוטומטי של שוכרים שהתעניינו בנכס שלך',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: provider.autoLikeEnabled,
            activeColor: AppColors.primary,
            activeTrackColor: AppColors.primary.withOpacity(0.3),
            inactiveThumbColor: const Color(0xFF94A3B8),
            inactiveTrackColor: const Color(0xFFE2E8F0),
            onChanged: (val) {
              HapticFeedback.mediumImpact();
              provider.toggleAutoLike();
            },
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

// ─── Lead Card ────────────────────────────────────────────────────────────────

class _LeadCard extends StatefulWidget {
  const _LeadCard({
    required this.tenant,
    required this.property,
    required this.reviews,
    required this.hOffset,
    required this.isHighFit,
    required this.fitReason,
  });

  final TenantProfile tenant;
  final RentalProperty property;
  final List<AppReview> reviews;
  final int hOffset;
  final bool isHighFit;
  final String? fitReason;

  @override
  State<_LeadCard> createState() => _LeadCardState();
}

class _LeadCardState extends State<_LeadCard> {
  int _photoIndex = 0;

  @override
  void didUpdateWidget(covariant _LeadCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenant.id != widget.tenant.id) {
      _photoIndex = 0;
      return;
    }
    _photoIndex = _safePhotoIndex(_photoIndex);
  }

  int _safePhotoIndex(int index) {
    final photoCount = widget.tenant.photoUrls.length;
    if (photoCount <= 0) return 0;
    return index.clamp(0, photoCount - 1).toInt();
  }

  void _prevImage() {
    final current = _safePhotoIndex(_photoIndex);
    if (current > 0) setState(() => _photoIndex = current - 1);
  }

  void _nextImage() {
    final current = _safePhotoIndex(_photoIndex);
    if (current < widget.tenant.photoUrls.length - 1) {
      setState(() => _photoIndex = current + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAccepting = widget.hOffset > 10;
    final isRejecting = widget.hOffset < -10;
    final photos = widget.tenant.photoUrls;
    final hasMultiple = photos.length > 1;
    final safePhotoIndex = _safePhotoIndex(_photoIndex);
    final currentPhoto = photos.isNotEmpty ? photos[safePhotoIndex] : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withOpacity(0.16),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.28),
              blurRadius: 18,
              spreadRadius: 2,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.white.withOpacity(0.08),
              blurRadius: 8,
              spreadRadius: -1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16.5),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Main Image
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: SafeImage(
                  key: ValueKey('${widget.tenant.id}:$safePhotoIndex:$currentPhoto'),
                  source: currentPhoto,
                  fallback: Container(
                    color: AppColors.navy,
                    child: const Center(
                      child: RentlyIcon(
                        IconsaxPlusLinear.profile_circle,
                        size: 80,
                        color: Colors.white24,
                      ),
                    ),
                  ),
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
              ),

              // Bottom dark gradient overlay
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black87,
                      Colors.black54,
                      Colors.black26,
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.35, 0.65, 0.85],
                  ),
                ),
              ),

              // Image navigation tap zones
              if (hasMultiple)
                Positioned.fill(
                  child: Column(
                    children: [
                      Expanded(
                        flex: 60,
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: _prevImage,
                                  behavior: HitTestBehavior.translucent,
                                  child: const SizedBox.expand(),
                                ),
                              ),
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
                      ),
                      const Spacer(flex: 40),
                    ],
                  ),
                ),

              // Tap bottom area -> detail page
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: MediaQuery.sizeOf(context).height * 0.32,
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TenantDetailScreen(
                          tenant: widget.tenant,
                          property: widget.property,
                          reviews: widget.reviews,
                        ),
                      ),
                    );
                  },
                  behavior: HitTestBehavior.translucent,
                ),
              ),

              // Stories-style progress bars
              if (hasMultiple)
                Positioned(
                  top: 12,
                  left: 14,
                  right: 14,
                  child: Row(
                    children: List.generate(photos.length, (i) {
                      return Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: i <= safePhotoIndex
                                ? Colors.white
                                : Colors.white.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      );
                    }),
                  ),
                ),

              // Top row: trust score or verification status badge
              Positioned(
                top: hasMultiple ? 26 : 16,
                right: 16,
                left: 16,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            IconsaxPlusLinear.shield_tick,
                            color: AppColors.primary,
                            size: 13,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'פרופיל מאומת',
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.isHighFit) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              IconsaxPlusBold.medal_star,
                              color: Colors.white,
                              size: 13,
                            ),
                            SizedBox(width: 5),
                            Text(
                              'התאמה גבוהה',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TenantDetailScreen(
                              tenant: widget.tenant,
                              property: widget.property,
                              reviews: widget.reviews,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.42),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
                          ),
                        ),
                        child: const Icon(
                          Icons.info_outline_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Swipe overlays
              if (isAccepting || isRejecting)
                Positioned(
                  top: 28,
                  left: isRejecting ? 22 : null,
                  right: isAccepting ? 22 : null,
                  child: Transform.rotate(
                    angle: isAccepting ? -0.15 : 0.15,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isAccepting ? AppColors.primary : AppColors.coral,
                          width: 3,
                        ),
                        color: (isAccepting ? AppColors.primary : AppColors.coral).withOpacity(0.08),
                      ),
                      child: Text(
                        isAccepting ? '✓ מאשר' : '✕ דוחה',
                        style: TextStyle(
                          color: isAccepting ? AppColors.primary : AppColors.coral,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),

              // Bottom Info Content
              Positioned(
                left: 16,
                right: 16,
                bottom: 128,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.tenant.name,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    if (widget.fitReason != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            IconsaxPlusBold.tick_circle,
                            color: Color(0xFF5AD4DC),
                            size: 14,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              widget.fitReason!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF5AD4DC),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _fmt(widget.tenant.budgetMax),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '/ לחודש',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _LikedPropertyBox(property: widget.property),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _StatPill(
                            icon: IconsaxPlusLinear.building,
                            label: '${widget.tenant.desiredRooms.toStringAsFixed(widget.tenant.desiredRooms % 1 == 0 ? 0 : 1)} חדרים',
                          ),
                          const SizedBox(width: 6),
                          _StatPill(
                            icon: IconsaxPlusLinear.calendar,
                            label: widget.tenant.moveInWindow,
                          ),
                          if (widget.tenant.importantDetails.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _StatPill(
                              icon: IconsaxPlusLinear.info_circle,
                              label: widget.tenant.importantDetails.first,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white.withOpacity(0.6)),
          const SizedBox(width: 5),
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

// ─── Liked property box ───────────────────────────────────────────────────────

class _LikedPropertyBox extends StatelessWidget {
  const _LikedPropertyBox({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF13BEC9).withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: RentlyIcon(
                    IconsaxPlusLinear.heart,
                    size: 16,
                    color: Color(0xFF5AD4DC),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'התעניין/ה בנכס:',
                      style: TextStyle(
                        color: Color(0xFF5AD4DC),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      property.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  property.priceLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
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

// ─── Action Buttons ───────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.onReject,
    required this.onAccept,
    required this.onInfo,
  });

  final VoidCallback onReject;
  final VoidCallback onAccept;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 56),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Accept button (Right in RTL)
          _ActionButton(
            icon: IconsaxPlusBold.heart,
            tooltip: 'אשר מועמד',
            iconColor: AppColors.primary,
            backgroundColor: Colors.white,
            size: 72,
            iconSize: 34,
            onPressed: onAccept,
            shadowColor: AppColors.primary,
          ),

          // Detail / Info (Center)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionButton(
                icon: Icons.info_outline_rounded,
                tooltip: 'הצג פרטים מלאים',
                iconColor: const Color(0xFF072946),
                backgroundColor: Colors.white,
                size: 56,
                iconSize: 26,
                onPressed: onInfo,
                shadowColor: const Color(0xFF072946),
              ),
              const SizedBox(height: 6),
              Text(
                'פרטים',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),

          // Reject button (Left in RTL)
          _ActionButton(
            icon: Icons.close_rounded,
            tooltip: 'דחה מועמד',
            iconColor: AppColors.coral,
            backgroundColor: Colors.white,
            size: 62,
            iconSize: 30,
            onPressed: onReject,
            shadowColor: AppColors.coral,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.iconColor,
    required this.backgroundColor,
    required this.size,
    required this.iconSize,
    required this.onPressed,
    this.shadowColor,
  });

  final IconData icon;
  final String tooltip;
  final Color iconColor;
  final Color backgroundColor;
  final double size;
  final double iconSize;
  final VoidCallback onPressed;
  final Color? shadowColor;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkCenter = widget.iconColor == const Color(0xFF072946);
    final actualIconColor = isDarkCenter ? Colors.white : widget.iconColor;

    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) async {
          await _ctrl.reverse();
          widget.onPressed();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (widget.shadowColor ?? Colors.black).withOpacity(0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.22),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      widget.icon,
                      size: widget.iconSize,
                      color: actualIconColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyOwnerQueue extends StatelessWidget {
  const _EmptyOwnerQueue();

  @override
  Widget build(BuildContext context) {
    final hasProperties = context.read<DatingProvider>().myProperties.isNotEmpty;
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
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: RentlyIcon(
                IconsaxPlusLinear.profile_2user,
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
                    MaterialPageRoute(builder: (_) => const AddPropertyScreen()),
                  ),
                  icon: const RentlyIcon(IconsaxPlusLinear.add_square, size: 17),
                  label: const Text('הוסף נכס עכשיו'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  icon: const RentlyIcon(IconsaxPlusLinear.message, size: 17),
                  label: const Text('עבור לשיחות'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.navy,
                    side: const BorderSide(color: AppColors.borderLight),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
