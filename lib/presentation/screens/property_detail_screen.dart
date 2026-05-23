import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class PropertyDetailScreen extends StatefulWidget {
  const PropertyDetailScreen({super.key, required this.property});
  final RentalProperty property;

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  RentalProperty get p => widget.property;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = p.imageUrls;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Image gallery as a plain SliverToBoxAdapter (no SliverAppBar conflict)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 340,
                  child: _ImageGallery(
                    images: images,
                    controller: _pageController,
                    currentPage: _currentPage,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    city: p.city,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PriceRow(property: p),
                      const SizedBox(height: 10),
                      _AddressRow(property: p),
                      const SizedBox(height: 20),
                      _StatsRow(property: p),
                      const SizedBox(height: 24),
                      _OwnerCard(property: p),
                      const SizedBox(height: 24),
                      if (p.features.isNotEmpty) ...[
                        _SectionTitle('מאפיינים'),
                        const SizedBox(height: 10),
                        _FeatureWrap(features: p.features),
                        const SizedBox(height: 24),
                      ],
                      _SectionTitle('פרטים נוספים'),
                      const SizedBox(height: 10),
                      _DetailsList(property: p),
                      const SizedBox(height: 24),
                      _SectionTitle('מיקום'),
                      const SizedBox(height: 10),
                      _MapSection(property: p),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Floating top bar (back + like buttons)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _FloatingNavBtn(
                    icon: IconsaxPlusLinear.arrow_right,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Consumer<DatingProvider>(
                    builder: (context, provider, _) => _FloatingNavBtn(
                      icon: provider.isSaved(p.id)
                          ? IconsaxPlusBold.bookmark
                          : IconsaxPlusLinear.bookmark,
                      onTap: () => provider.toggleSave(p.id),
                      tint: provider.isSaved(p.id)
                          ? AppColors.primary
                          : Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _FloatingNavBtn(
                    icon: IconsaxPlusLinear.heart,
                    onTap: () {
                      context.read<DatingProvider>().likeProperty(p.id);
                      Navigator.of(context).pop();
                    },
                    tint: AppColors.coral,
                  ),
                ],
              ),
            ),
          ),

          // Bottom action bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomBar(property: p),
          ),
        ],
      ),
    );
  }
}

// ─── Image Gallery ────────────────────────────────────────────────────────────

class _ImageGallery extends StatelessWidget {
  const _ImageGallery({
    required this.images,
    required this.controller,
    required this.currentPage,
    required this.onPageChanged,
    required this.city,
  });

  final List<String> images;
  final PageController controller;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final String city;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        images.isEmpty
            ? _ImageFallback(city: city)
            : PageView.builder(
                controller: controller,
                onPageChanged: onPageChanged,
                itemCount: images.length,
                itemBuilder: (_, i) => Image.network(
                  images[i],
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _ImageFallback(city: city),
                ),
              ),

        // Invisible tap zones for gallery navigation
        if (images.length > 1)
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      if (currentPage > 0) {
                        controller.previousPage(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      if (currentPage < images.length - 1) {
                        controller.nextPage(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

        // Bottom gradient
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xCC072946), Colors.transparent],
                stops: [0.0, 0.55],
              ),
            ),
          ),
        ),

        // Carousel indicator at bottom
        if (images.length > 1)
          Positioned(
            bottom: 18,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: _CarouselDots(count: images.length, current: currentPage),
            ),
          ),

        // Image counter badge (top right)
        if (images.length > 1)
          Positioned(
            top: 60,
            left: 16,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(IconsaxPlusBold.gallery,
                        size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      '${currentPage + 1} / ${images.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CarouselDots extends StatelessWidget {
  const _CarouselDots({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 22 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary
                : Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
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
            const Icon(IconsaxPlusBold.building,
                size: 64, color: Colors.white30),
            if (city.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(city,
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Floating navigation buttons ─────────────────────────────────────────────

class _FloatingNavBtn extends StatelessWidget {
  const _FloatingNavBtn(
      {required this.icon, required this.onTap, this.tint});
  final IconData icon;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.38),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: tint ?? Colors.white, size: 20),
      ),
    );
  }
}

// ─── Owner Card ───────────────────────────────────────────────────────────────

class _OwnerCard extends StatelessWidget {
  const _OwnerCard({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final reviews = provider.propertyReviews(property.id);
        final avgRating = provider.reviewAverage(reviews);
        final initial = property.ownerName.isNotEmpty
            ? property.ownerName[0].toUpperCase()
            : '?';
        final isAgency = property.agencyListing;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: const [
              BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 12,
                  offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Avatar
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: isAgency
                          ? AppColors.primary
                          : AppColors.navy,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          property.ownerName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(
                                color: isAgency
                                    ? AppColors.primaryLight2
                                    : const Color(0xFFFFF3E0),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isAgency
                                        ? IconsaxPlusBold.verify
                                        : IconsaxPlusBold.home_2,
                                    size: 11,
                                    color: isAgency
                                        ? AppColors.primary
                                        : const Color(0xFFE67E22),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isAgency ? 'מתווך מאומת' : 'בעל דירה',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isAgency
                                          ? AppColors.primary
                                          : const Color(0xFFE67E22),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (reviews.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              const Icon(IconsaxPlusBold.star_1,
                                  size: 13, color: Color(0xFFE8A84A)),
                              const SizedBox(width: 3),
                              Text(
                                avgRating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navy,
                                ),
                              ),
                              Text(
                                ' (${reviews.length})',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (reviews.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(height: 1, color: AppColors.borderLight),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _showOwnerSheet(context, property, reviews),
                  child: Row(
                    children: [
                      const Icon(IconsaxPlusLinear.star,
                          size: 15, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        'ביקורות על ${property.ownerName}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      const Icon(IconsaxPlusLinear.arrow_left,
                          size: 14, color: AppColors.primary),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _showOwnerSheet(context, property, reviews),
                child: Row(
                  children: [
                    const Icon(IconsaxPlusLinear.profile_circle,
                        size: 15, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    const Text(
                      'צפה בפרופיל המלא',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    const Icon(IconsaxPlusLinear.arrow_left,
                        size: 14, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showOwnerSheet(
      BuildContext context, RentalProperty property, List<AppReview> reviews) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OwnerProfileSheet(property: property, reviews: reviews),
    );
  }
}

class _OwnerProfileSheet extends StatelessWidget {
  const _OwnerProfileSheet(
      {required this.property, required this.reviews});
  final RentalProperty property;
  final List<AppReview> reviews;

  @override
  Widget build(BuildContext context) {
    final initial = property.ownerName.isNotEmpty
        ? property.ownerName[0].toUpperCase()
        : '?';
    final isAgency = property.agencyListing;
    final avgRating = reviews.isEmpty
        ? 0.0
        : reviews.fold<int>(0, (s, r) => s + r.rating) / reviews.length;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          // Owner header
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: isAgency
                        ? AppColors.primary
                        : Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        property.ownerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        isAgency ? 'מתווך נדל"ן מאומת' : 'בעל דירה פרטי',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      if (reviews.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(IconsaxPlusBold.star_1,
                                size: 14, color: Color(0xFFE8A84A)),
                            const SizedBox(width: 4),
                            Text(
                              '${avgRating.toStringAsFixed(1)} · ${reviews.length} ביקורות',
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (reviews.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'ביקורות (${reviews.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.35,
              ),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                shrinkWrap: true,
                itemCount: reviews.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _ReviewTile(review: reviews[i]),
              ),
            ),
          ] else ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Text(
                'עוד אין ביקורות על המשכיר הזה.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});
  final AppReview review;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ...List.generate(
                  5,
                  (i) => Icon(
                        i < review.rating
                            ? IconsaxPlusBold.star_1
                            : IconsaxPlusLinear.star,
                        size: 13,
                        color: i < review.rating
                            ? const Color(0xFFE8A84A)
                            : AppColors.borderLight,
                      )),
              const SizedBox(width: 8),
              Text(
                review.authorName,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            review.text,
            style: const TextStyle(
                color: AppColors.navy, fontSize: 13, height: 1.45),
          ),
        ],
      ),
    );
  }
}

// ─── Content widgets ──────────────────────────────────────────────────────────

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          property.priceLabel,
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(width: 6),
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text(
            'לחודש',
            style: TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(IconsaxPlusLinear.location,
            size: 18, color: AppColors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            property.address,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          _StatCell(
              icon: IconsaxPlusBold.building,
              value: '${property.roomsLabel} חדרים'),
          _StatDivider(),
          _StatCell(
              icon: IconsaxPlusBold.maximize_3,
              value: '${property.sizeM2} מ"ר'),
          if (property.floor.isNotEmpty) ...[
            _StatDivider(),
            _StatCell(
                icon: IconsaxPlusBold.layer,
                value: 'קומה ${property.floor}'),
          ],
          if (property.entryDate.isNotEmpty) ...[
            _StatDivider(),
            _StatCell(
                icon: IconsaxPlusBold.calendar, value: property.entryDate),
          ],
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.icon, required this.value});
  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(height: 5),
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 36, color: AppColors.borderLight);
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.navy),
    );
  }
}

class _FeatureWrap extends StatelessWidget {
  const _FeatureWrap({required this.features});
  final List<String> features;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: features.map((f) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primaryLight2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Text(
            f,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary),
          ),
        );
      }).toList(),
    );
  }
}

class _DetailsList extends StatelessWidget {
  const _DetailsList({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    final items = [
      if (property.propertyType.isNotEmpty)
        _DetailItem(
            icon: IconsaxPlusBold.building,
            label: 'סוג נכס',
            value: property.propertyType),
      if (property.condition.isNotEmpty)
        _DetailItem(
            icon: IconsaxPlusBold.star,
            label: 'מצב הנכס',
            value: property.condition),
      if (property.totalFloors.isNotEmpty)
        _DetailItem(
            icon: IconsaxPlusBold.layer,
            label: 'קומות בבניין',
            value: property.totalFloors),
    ];

    if (items.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: items.length == 1 ? 1 : (items.length == 2 ? 2 : 3),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: items.length == 1 ? 4.5 : 1.45,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final d = items[i];
        return Container(
          padding: const EdgeInsets.all(14),
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(d.icon, size: 18, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                d.value,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                d.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                  height: 1.2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DetailItem {
  const _DetailItem(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
}

class _MapSection extends StatelessWidget {
  const _MapSection({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openInMaps(property.lat, property.lon),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 200,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(property.lat, property.lon),
                  initialZoom: 15,
                  interactionOptions:
                      const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.rentch.app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(property.lat, property.lon),
                        width: 44,
                        height: 44,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x4413BEC9),
                                  blurRadius: 10,
                                  offset: Offset(0, 4)),
                            ],
                          ),
                          child: const Icon(IconsaxPlusBold.building,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // "Open in maps" hint pill
              Positioned(
                bottom: 12,
                right: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(IconsaxPlusLinear.export_2,
                          size: 13, color: Colors.white),
                      SizedBox(width: 5),
                      Text(
                        'פתח במפות',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openInMaps(double lat, double lon) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lon',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 20, offset: Offset(0, -6)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(IconsaxPlusLinear.arrow_right),
              label: const Text('חזרה'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.navy,
                side: const BorderSide(color: AppColors.borderLight),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Consumer<DatingProvider>(
              builder: (context, provider, _) => FilledButton.icon(
                onPressed: () {
                  provider.likeProperty(property.id);
                  Navigator.of(context).pop();
                },
                icon: const Icon(IconsaxPlusBold.heart),
                label: const Text('אהבתי!'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
