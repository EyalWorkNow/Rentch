import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/presentation/widgets/safe_image.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';

class TenantDetailScreen extends StatefulWidget {
  const TenantDetailScreen({
    super.key,
    required this.tenant,
    required this.property,
    required this.reviews,
  });

  final TenantProfile tenant;
  final RentalProperty property;
  final List<AppReview> reviews;

  @override
  State<TenantDetailScreen> createState() => _TenantDetailScreenState();
}

class _TenantDetailScreenState extends State<TenantDetailScreen> {
  int _activePhotoIndex = 0;
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.tenant.photoUrls;
    final hasPhotos = photos.isNotEmpty;
    final double appBarHeight = MediaQuery.sizeOf(context).height * 0.42;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ─── Collapsible Header / Photo Gallery ──────────────────────
          SliverAppBar(
            expandedHeight: appBarHeight,
            automaticallyImplyLeading: false,
            pinned: true,
            stretch: true,
            backgroundColor: AppColors.navy,
            surfaceTintColor: Colors.transparent,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [
                StretchMode.zoomBackground,
                StretchMode.blurBackground,
              ],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasPhotos) ...[
                    PageView.builder(
                      controller: _pageController,
                      itemCount: photos.length,
                      onPageChanged: (index) {
                        setState(() => _activePhotoIndex = index);
                      },
                      itemBuilder: (context, index) {
                        return SafeImage(
                          source: photos[index],
                          fit: BoxFit.cover,
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
                        );
                      },
                    ),
                    // Photo dots
                    if (photos.length > 1)
                      Positioned(
                        bottom: 48,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(photos.length, (i) {
                            final isActive = i == _activePhotoIndex;
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
                        ),
                      ),
                  ] else
                    Container(
                      color: AppColors.navy,
                      child: const Center(
                        child: RentlyIcon(
                          IconsaxPlusLinear.profile_circle,
                          size: 100,
                          color: Colors.white24,
                        ),
                      ),
                    ),
                  // Dark bottom gradient overlay
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Color(0xF2072946),
                          Color(0x33072946),
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.4, 0.7],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ─── Scrollable Profile Details ─────────────────────────────
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -32),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name & Basic Title
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.tenant.name,
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.navy,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  RentlyIcon(
                                    IconsaxPlusLinear.verify,
                                    size: 16,
                                    color: AppColors.primary,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'משתמש מאומת',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Key Preferences Grid
                    Row(
                      children: [
                        Expanded(
                          child: _DetailCardItem(
                            icon: IconsaxPlusLinear.wallet,
                            title: 'תקציב מקסימלי',
                            value: _fmt(widget.tenant.budgetMax),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DetailCardItem(
                            icon: IconsaxPlusLinear.building_3,
                            title: 'חדרים מבוקשים',
                            value:
                                '${widget.tenant.desiredRooms.toStringAsFixed(widget.tenant.desiredRooms % 1 == 0 ? 0 : 1)} חדרים',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _DetailCardItem(
                            icon: IconsaxPlusLinear.calendar,
                            title: 'מועד כניסה',
                            value: widget.tenant.moveInWindow,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DetailCardItem(
                            icon: IconsaxPlusLinear.shield_security,
                            title: 'נקודות אמון',
                            value:
                                '85 נקודות', // Mock or trust score if available
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Liked Property Showcase Card
                    const Text(
                      'הנכס המבוקש',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _LikedPropertyDetailedCard(property: widget.property),
                    const SizedBox(height: 24),

                    // Bio Section
                    if (widget.tenant.bio.isNotEmpty) ...[
                      const Text(
                        'קצת עלי',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.borderLight),
                          boxShadow: const [
                            BoxShadow(
                              color: AppColors.shadow,
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          widget.tenant.bio,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                            height: 1.6,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Important Tags/Preferences Wrap
                    if (widget.tenant.importantDetails.isNotEmpty) ...[
                      const Text(
                        'העדפות ותגיות',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.tenant.importantDetails.map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.borderLight),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 28),
                    ],

                    // Reviews List
                    if (widget.reviews.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'המלצות מבעלי דירות קודמים',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF9E6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const RentlyIcon(
                                  IconsaxPlusLinear.star_1,
                                  color: Color(0xFFF39C12),
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _avgRating(widget.reviews),
                                  style: const TextStyle(
                                    color: Color(0xFFB37400),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: widget.reviews.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final review = widget.reviews[index];
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.borderLight),
                              boxShadow: const [
                                BoxShadow(
                                  color: AppColors.shadow,
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      review.authorName,
                                      style: const TextStyle(
                                        color: AppColors.navy,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Row(
                                      children: List.generate(5, (i) {
                                        return Icon(
                                          i < review.rating
                                              ? IconsaxPlusLinear.star_1
                                              : IconsaxPlusLinear.star,
                                          color: const Color(0xFFF39C12),
                                          size: 13,
                                        );
                                      }),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '"${review.text}"',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                    height: 1.5,
                                    fontWeight: FontWeight.w500,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _avgRating(List<AppReview> reviews) {
    if (reviews.isEmpty) return '0.0';
    final avg = reviews.fold(0, (s, r) => s + r.rating) / reviews.length;
    return avg.toStringAsFixed(1);
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
}

class _DetailCardItem extends StatelessWidget {
  const _DetailCardItem({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
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

class _LikedPropertyDetailedCard extends StatelessWidget {
  const _LikedPropertyDetailedCard({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    final image = property.imageUrl;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (image.isNotEmpty)
              SizedBox(
                height: 140,
                width: double.infinity,
                child: SafeImage(
                  source: image,
                  fit: BoxFit.cover,
                  fallback: Container(
                    color: AppColors.navy,
                    child: const Center(
                      child: RentlyIcon(
                        IconsaxPlusLinear.building,
                        size: 40,
                        color: Colors.white24,
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          property.propertyType,
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          property.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const RentlyIcon(
                              IconsaxPlusLinear.building,
                              size: 13,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${property.roomsLabel} חדרים',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const RentlyIcon(
                              IconsaxPlusLinear.maximize_3,
                              size: 13,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${property.sizeM2} מ״ר',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          property.priceLabel,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          property.priceSuffixLabel,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
