import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/widgets/property_share_sheet.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
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
  bool get _hasVirtualTour => p.videoUrls.isNotEmpty;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = p.media;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Image gallery as a plain SliverToBoxAdapter (no SliverAppBar conflict)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 390,
                  child: _ImageGallery(
                    media: media,
                    controller: _pageController,
                    currentPage: _currentPage,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    city: p.city,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _OverviewCard(
                        property: p,
                        hasVirtualTour: _hasVirtualTour,
                        onTourTap: () => openPropertyTour(context, p),
                      ),
                      const SizedBox(height: 16),
                      _SectionCardShell(
                        title: 'פרטי הדירה',
                        icon: IconsaxPlusBold.building_4,
                        child: Column(
                          children: [
                            _PrimaryFactsGrid(property: p),
                            const SizedBox(height: 14),
                            _DetailsList(property: p),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCardShell(
                        title: 'בעל הנכס',
                        icon: IconsaxPlusBold.profile_2user,
                        child: _OwnerCard(property: p),
                      ),
                      if (p.features.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _SectionCardShell(
                          title: 'מאפיינים חשובים',
                          icon: IconsaxPlusBold.flash_1,
                          child: _FeatureWrap(features: p.features),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _SectionCardShell(
                        title: 'מיקום',
                        icon: IconsaxPlusBold.location,
                        child: _MapSection(property: p),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Floating top bar (back + share buttons)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _FloatingNavBtn(
                    icon: IconsaxPlusBold.arrow_right,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  _FloatingNavBtn(
                    icon: IconsaxPlusBold.send_2,
                    onTap: () => showPropertyShareSheet(context, p),
                    tint: Colors.white,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),

          // Bottom action bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomBar(
              property: p,
              hasVirtualTour: _hasVirtualTour,
              onLike: () {
                context.read<DatingProvider>().likeProperty(p.id);
                Navigator.of(context).pop();
              },
              onTour: () => openPropertyTour(context, p),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Image Gallery ────────────────────────────────────────────────────────────

class _ImageGallery extends StatelessWidget {
  const _ImageGallery({
    required this.media,
    required this.controller,
    required this.currentPage,
    required this.onPageChanged,
    required this.city,
  });

  final List<PropertyMedia> media;
  final PageController controller;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final String city;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        media.isEmpty
            ? _ImageFallback(city: city)
            : PageView.builder(
                controller: controller,
                onPageChanged: onPageChanged,
                itemCount: media.length,
                itemBuilder: (_, i) => SafeMedia(
                  media: media[i],
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  fallback: _ImageFallback(city: city),
                  videoMode: SafeVideoDisplayMode.playback,
                ),
              ),

        // Invisible tap zones for gallery navigation
        if (media.length > 1)
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
                      if (currentPage < media.length - 1) {
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
        if (media.length > 1)
          Positioned(
            bottom: 18,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: _CarouselDots(count: media.length, current: currentPage),
            ),
          ),

        // Image counter badge (top right)
        if (media.length > 1)
          Positioned(
            top: 60,
            left: 16,
            child: IgnorePointer(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                      '${currentPage + 1} / ${media.length}',
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
        if (media.isNotEmpty && media[currentPage].isVideo)
          Positioned(
            top: 60,
            right: 16,
            child: IgnorePointer(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(IconsaxPlusBold.video, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'וידאו',
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
  const _FloatingNavBtn({required this.icon, required this.onTap, this.tint});
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

Future<void> openPropertyTour(
  BuildContext context,
  RentalProperty property,
) async {
  if (property.videoUrls.isEmpty) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _TourUnavailableSheet(property: property),
    );
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _VirtualTourScreen(property: property),
    ),
  );
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Avatar
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isAgency ? AppColors.primary : AppColors.navy,
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
                              horizontal: 9,
                              vertical: 3,
                            ),
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
                            const Icon(
                              IconsaxPlusBold.star_1,
                              size: 13,
                              color: Color(0xFFE8A84A),
                            ),
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
                                color: AppColors.textSecondary,
                              ),
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
                    const Icon(IconsaxPlusBold.star,
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
                    const Icon(IconsaxPlusBold.arrow_left,
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
                  const Icon(IconsaxPlusBold.profile_circle,
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
                  const Icon(IconsaxPlusBold.arrow_left,
                      size: 14, color: AppColors.textSecondary),
                ],
              ),
            ),
          ],
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
  const _OwnerProfileSheet({required this.property, required this.reviews});
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
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
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
                            : IconsaxPlusBold.star,
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

class _PrimaryFactsGrid extends StatelessWidget {
  const _PrimaryFactsGrid({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    final items = <_FactDetailItem>[
      _FactDetailItem(
        icon: IconsaxPlusBold.building,
        value: property.roomsLabel,
        label: 'חדרים',
      ),
      _FactDetailItem(
        icon: IconsaxPlusBold.maximize_3,
        value: property.sizeM2.toString(),
        label: 'מ"ר',
      ),
      if (property.floor.isNotEmpty)
        _FactDetailItem(
          icon: IconsaxPlusBold.layer,
          value: property.floor,
          label: 'קומה',
        ),
      if (property.entryDate.isNotEmpty)
        _FactDetailItem(
          icon: IconsaxPlusBold.calendar,
          value: _formatEntryDate(property.entryDate),
          label: 'כניסה',
        ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.7,
      ),
      itemBuilder: (_, index) => _FactDetailCard(item: items[index]),
    );
  }
}

class _FactDetailItem {
  const _FactDetailItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;
}

class _FactDetailCard extends StatelessWidget {
  const _FactDetailCard({required this.item});

  final _FactDetailItem item;

  @override
  Widget build(BuildContext context) {
    final iconBadge = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(item.icon, size: 18, color: AppColors.primary),
    );

    final textBlock = Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0EBF2)),
      ),
      child: Row(
        children: [
          iconBadge,
          const SizedBox(width: 12),
          textBlock,
        ],
      ),
    );
  }
}

class _SectionCardShell extends StatelessWidget {
  const _SectionCardShell({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2ECF1)),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _FeatureWrap extends StatelessWidget {
  const _FeatureWrap({required this.features});
  final List<String> features;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: features.map((f) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFD),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE0EBF2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                IconsaxPlusBold.tick_circle,
                size: 14,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                f,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
            ],
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

    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          _SecondaryDetailRow(item: items[i]),
          if (i != items.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: AppColors.borderLight),
            ),
        ],
      ],
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

class _SecondaryDetailRow extends StatelessWidget {
  const _SecondaryDetailRow({required this.item});

  final _DetailItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(item.icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _formatEntryDate(String rawValue) {
  final parsed = DateTime.tryParse(rawValue);
  if (parsed == null) return rawValue;
  final dd = parsed.day.toString().padLeft(2, '0');
  final mm = parsed.month.toString().padLeft(2, '0');
  final yyyy = parsed.year.toString();
  return '$dd/$mm/$yyyy';
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
                      Icon(IconsaxPlusBold.export_2,
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
  const _BottomBar({
    required this.property,
    required this.hasVirtualTour,
    required this.onLike,
    required this.onTour,
  });
  final RentalProperty property;
  final bool hasVirtualTour;
  final VoidCallback onLike;
  final VoidCallback onTour;

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
              onPressed: onLike,
              icon: const Icon(IconsaxPlusBold.heart),
              label: const Text('אהבתי'),
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
            child: FilledButton.icon(
              onPressed: onTour,
              icon: const Icon(Icons.view_in_ar_rounded),
              label: Text(hasVirtualTour ? 'סיור תלת־ממדי' : 'בקש סיור תלת־ממדי'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.property,
    required this.hasVirtualTour,
    required this.onTourTap,
  });

  final RentalProperty property;
  final bool hasVirtualTour;
  final VoidCallback onTourTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE2ECF1)),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetaPill(
                          icon: property.transactionType ==
                                  PropertyTransactionType.sale
                              ? IconsaxPlusBold.tag
                              : IconsaxPlusBold.key,
                          label: property.transactionLabel,
                        ),
                        if (property.propertyType.trim().isNotEmpty)
                          _MetaPill(
                            icon: IconsaxPlusBold.building_4,
                            label: property.propertyType,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
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
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            property.priceSuffixLabel,
                            style: const TextStyle(
                              fontSize: 15,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          IconsaxPlusBold.location,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            property.address,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _CompactFactsRow(property: property),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onTourTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0B3957), Color(0xFF0F5478)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.view_in_ar_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasVirtualTour
                              ? 'סיור תלת־ממדי זמין עכשיו'
                              : 'אין עדיין סריקת 3D לנכס הזה',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasVirtualTour
                              ? 'פתח סיור עצמי ועבור בין חללי הדירה'
                              : 'אפשר לפתוח בקשה לסריקה או לצפות במדיה הקיימת',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    IconsaxPlusBold.arrow_left_2,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF4FAFD),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD9EAF2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactFactsRow extends StatelessWidget {
  const _CompactFactsRow({required this.property});

  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FactChip(
          icon: IconsaxPlusBold.building,
          label: '${property.roomsLabel} חדרים',
        ),
        _FactChip(
          icon: IconsaxPlusBold.maximize_3,
          label: '${property.sizeM2} מ"ר',
        ),
        if (property.floor.isNotEmpty)
          _FactChip(
            icon: IconsaxPlusBold.layer,
            label: 'קומה ${property.floor}',
          ),
      ],
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0EBF2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TourUnavailableSheet extends StatelessWidget {
  const _TourUnavailableSheet({required this.property});

  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.primaryLight2,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.view_in_ar_rounded,
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'עדיין אין סיור תלת־ממדי לנכס הזה',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'כדי לפתוח הליכה חופשית בתוך הדירה צריך שתהיה סריקה או וידאו ייעודי של הנכס. כרגע אפשר להמשיך דרך התמונות והמודעה המקורית.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(IconsaxPlusBold.close_circle),
                  label: const Text('סגור'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await launchUrl(
                      Uri.parse(property.url),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  icon: const Icon(IconsaxPlusBold.export_2),
                  label: const Text('פתח מודעה'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VirtualTourScreen extends StatelessWidget {
  const _VirtualTourScreen({required this.property});

  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    final tourMedia = property.media.where((item) => item.isVideo).toList();
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              itemCount: tourMedia.length,
              itemBuilder: (_, index) => SafeMedia(
                media: tourMedia[index],
                fit: BoxFit.contain,
                videoMode: SafeVideoDisplayMode.playback,
                fallback: const Center(
                  child: Icon(
                    Icons.view_in_ar_rounded,
                    color: Colors.white30,
                    size: 54,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  _FloatingNavBtn(
                    icon: IconsaxPlusBold.arrow_right,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.view_in_ar_rounded,
                            size: 16, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'סיור תלת־ממדי',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 24,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      property.address,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'גרור בין קטעי הסיור כדי להרגיש את החלל לפני ביקור פיזי.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
