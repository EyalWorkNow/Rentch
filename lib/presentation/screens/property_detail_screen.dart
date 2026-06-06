import 'dart:async';
import 'dart:ui';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/widgets/property_share_sheet.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rentch_icon.dart';
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
  DatingProvider? _analyticsProvider;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<DatingProvider>();
      _analyticsProvider = provider;
      provider.beginPropertyDetailView(widget.property.id);
    });
  }

  @override
  void dispose() {
    unawaited(
      _analyticsProvider?.endPropertyDetailView(widget.property.id) ??
          Future<void>.value(),
    );
    _pageController.dispose();
    super.dispose();
  }

  void _handleGalleryPageChanged(String propertyId, int index) {
    setState(() => _currentPage = index);
    context.read<DatingProvider>().recordPropertyGallerySwipe(
          propertyId,
          index,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final p = provider.propertyById(widget.property.id) ?? widget.property;
        final media = p.media;
        final hasVirtualTour = p.hasReadyVirtualTour || p.videoUrls.isNotEmpty;
        final title = p.street.isNotEmpty
            ? '${p.propertyType} ב${p.street} ${p.streetNumber}'
            : '${p.propertyType} ב${p.city}';
        final reviews = provider.propertyReviews(p.id);
        final avgRating = provider.reviewAverage(reviews);

        return Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  // Image Gallery wrapped in a padded rounded card (Mockup Style)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 50, 16, 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: SizedBox(
                          height: 380,
                          child: _ImageGallery(
                            property: p,
                            controller: _pageController,
                            currentPage: _currentPage,
                            onPageChanged: (i) =>
                                _handleGalleryPageChanged(p.id, i),
                            avgRating: avgRating,
                            onBackTap: () => Navigator.of(context).pop(),
                            onShareTap: () =>
                                showPropertyShareSheet(context, p),
                          ),
                        ),
                      ),
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 140),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title & Location & Favorite Heart Icon Row (Mockup Style)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        color: Color(0xFF0F172A),
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const RentchIcon(
                                            IconsaxPlusLinear.location,
                                            size: 16,
                                            color: Color(0xFF64748B)),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            p.address,
                                            style: const TextStyle(
                                              color: Color(0xFF64748B),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
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
                          const SizedBox(height: 24),
                          if (_PropertySignalStrip.shouldShow(context, p)) ...[
                            _PropertySignalStrip(property: p),
                            const SizedBox(height: 24),
                          ],

                          // Photos / Gallery Carousel (Mockup Style)
                          if (media.isNotEmpty) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'גלריה',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  '${media.length} תמונות',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 105,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: media.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (context, index) {
                                  final item = media[index];
                                  return GestureDetector(
                                    onTap: () {
                                      _pageController.animateToPage(
                                        index,
                                        duration:
                                            const Duration(milliseconds: 300),
                                        curve: Curves.easeInOut,
                                      );
                                    },
                                    child: Column(
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          child: SizedBox(
                                            width: 100,
                                            height: 70,
                                            child: SafeMedia(
                                              media: item,
                                              fit: BoxFit.cover,
                                              fallback:
                                                  _ImageFallback(city: p.city),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          item.isVideo
                                              ? 'סרטון'
                                              : 'תמונה ${index + 1}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Property Facts Grid Card (Mockup Style)
                          const Text(
                            'פרטי הנכס',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _PropertyFactsCard(p),
                          const SizedBox(height: 24),

                          // Description / Website URL Section
                          if (p.url.isNotEmpty) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'אתר מקור',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () async {
                                    await launchUrl(Uri.parse(p.url),
                                        mode: LaunchMode.externalApplication);
                                  },
                                  child: const Text(
                                    'צפה במקור',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF13BEC9),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'נכס זה פורסם במקור באתר ${Uri.parse(p.url).host}. באפשרותך לפתוח את המודעה המקורית לצפייה בפרטים המלאים.',
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                fontSize: 13.5,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Owners Section
                          _SectionCardShell(
                            title: 'בעל הנכס',
                            icon: IconsaxPlusLinear.profile_2user,
                            child: _OwnerCard(property: p),
                          ),

                          // Features Section
                          if (p.features.isNotEmpty) ...[
                            _SectionCardShell(
                              title: 'מאפיינים חשובים',
                              icon: IconsaxPlusLinear.flash_1,
                              child: _FeatureWrap(features: p.features),
                            ),
                          ],

                          // Reviews Section (Mockup Style)
                          if (reviews.isNotEmpty) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'חוות דעת',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  '${reviews.length} ביקורות',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _HorizontalReviewsList(reviews),
                            const SizedBox(height: 24),
                          ],

                          // Location Map Section
                          _SectionCardShell(
                            title: 'מיקום',
                            icon: IconsaxPlusLinear.location,
                            child: _MapSection(property: p),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // Floating share button at bottom left
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 85,
                left: 20,
                child: GestureDetector(
                  onTap: () => showPropertyShareSheet(context, p),
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const RentchIcon(
                      IconsaxPlusLinear.export_2,
                      color: Colors.black,
                      size: 24,
                    ),
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
                  hasVirtualTour: hasVirtualTour,
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
      },
    );
  }
}

// ─── Image Gallery ────────────────────────────────────────────────────────────

class _ImageGallery extends StatelessWidget {
  const _ImageGallery({
    required this.property,
    required this.controller,
    required this.currentPage,
    required this.onPageChanged,
    required this.avgRating,
    required this.onBackTap,
    required this.onShareTap,
  });

  final RentalProperty property;
  final PageController controller;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final double avgRating;
  final VoidCallback onBackTap;
  final VoidCallback onShareTap;

  @override
  Widget build(BuildContext context) {
    final media = property.media;
    final safeCurrentPage =
        media.isEmpty ? 0 : currentPage.clamp(0, media.length - 1).toInt();

    return Stack(
      fit: StackFit.expand,
      children: [
        media.isEmpty
            ? _ImageFallback(city: property.city)
            : PageView.builder(
                controller: controller,
                onPageChanged: onPageChanged,
                itemCount: media.length,
                itemBuilder: (_, i) => SafeMedia(
                  media: media[i],
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  fallback: _ImageFallback(city: property.city),
                  videoMode: SafeVideoDisplayMode.playback,
                ),
              ),

        // Invisible tap zones for gallery navigation
        if (media.length > 1)
          Positioned.fill(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        if (safeCurrentPage > 0) {
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
                        if (safeCurrentPage < media.length - 1) {
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
          ),

        // Bottom dark gradient overlay for text readability
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 140,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.black.withOpacity(0.4),
                    Colors.black.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Navigation controls overlay
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Back Button (Mockup style circular white)
              GestureDetector(
                onTap: onBackTap,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const RentchIcon(
                    IconsaxPlusLinear.arrow_right_3,
                    color: Color(0xFF0F172A),
                    size: 20,
                  ),
                ),
              ),
              // Share Button (Mockup style circular white)
              GestureDetector(
                onTap: onShareTap,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const RentchIcon(
                    IconsaxPlusLinear.export_2,
                    color: Color(0xFF0F172A),
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Bottom text and badge overlays (Mockup style)
        Positioned(
          bottom: 20,
          right: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF13BEC9).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF13BEC9).withOpacity(0.3)),
                ),
                child: Text(
                  property.transactionLabel,
                  style: const TextStyle(
                    color: Color(0xFF13BEC9),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${property.priceLabel} ${property.priceSuffixLabel}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),

        // Carousel indicator dots
        if (media.length > 1)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: _CarouselDots(
                count: media.length,
                current: safeCurrentPage,
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
            const RentchIcon(IconsaxPlusLinear.building,
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: Icon(icon, color: tint ?? Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

class _DarkCapsuleTag extends StatelessWidget {
  const _DarkCapsuleTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MetadataGrid extends StatelessWidget {
  const _MetadataGrid({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildColumn(context, 'שטח כולל', '${property.sizeM2} מ"ר'),
        _buildColumn(context, 'מספר חדרים', property.roomsLabel),
        _buildColumn(
            context, 'תאריך כניסה', _formatEntryDate(property.entryDate)),
      ],
    );
  }

  Widget _buildColumn(BuildContext context, String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> openPropertyTour(
  BuildContext context,
  RentalProperty property,
) async {
  if (!property.hasReadyVirtualTour && property.videoUrls.isEmpty) {
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

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Avatar with Verified Badge Overlay
                  Stack(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isAgency
                                ? [
                                    const Color(0xFF13BEC9),
                                    const Color(0xFF0D9BA4)
                                  ]
                                : [
                                    const Color(0xFF475569),
                                    const Color(0xFF1E293B)
                                  ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
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
                      if (isAgency)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2.0),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const RentchIcon(
                              IconsaxPlusLinear.verify,
                              size: 16,
                              color: Color(0xFF13BEC9),
                            ),
                          ),
                        ),
                    ],
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
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isAgency ? 'מתווך נדל"ן מאומת' : 'בעל נכס פרטי',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isAgency
                                ? const Color(0xFF13BEC9)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (reviews.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF08A).withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const RentchIcon(
                            IconsaxPlusLinear.star_1,
                            size: 14,
                            color: Color(0xFFCA8A04),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            avgRating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF854D0E),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'פרטי בעל הנכס, הדירוגים והערות השוכרים הקודמים זמינים כאן בשקיפות מלאה.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w500,
                ),
              ),

              // Real review quote bubble if available
              if (reviews.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.format_quote_rounded,
                        size: 18,
                        color: Color(0xFF13BEC9),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '"${reviews.first.text}"',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontStyle: FontStyle.italic,
                            color: Color(0xFF475569),
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => _showOwnerSheet(context, property, reviews),
                    child: Row(
                      children: [
                        const RentchIcon(IconsaxPlusLinear.profile_circle,
                            size: 16, color: Color(0xFF13BEC9)),
                        const SizedBox(width: 6),
                        const Text(
                          'פרופיל משכיר וביקורות',
                          style: TextStyle(
                            color: Color(0xFF13BEC9),
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '(${reviews.length} חוות דעת)',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const RentchIcon(
                    IconsaxPlusLinear.arrow_left,
                    size: 14,
                    color: Color(0xFF13BEC9),
                  ),
                ],
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
                            const RentchIcon(IconsaxPlusLinear.star_1,
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
                            ? IconsaxPlusLinear.star_1
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

class _PrimaryFactsGrid extends StatelessWidget {
  const _PrimaryFactsGrid({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    final items = <_FactDetailItem>[
      _FactDetailItem(
        icon: IconsaxPlusLinear.building,
        value: property.roomsLabel,
        label: 'חדרים',
      ),
      _FactDetailItem(
        icon: IconsaxPlusLinear.maximize_3,
        value: property.sizeM2.toString(),
        label: 'מ"ר',
      ),
      if (property.floor.isNotEmpty)
        _FactDetailItem(
          icon: IconsaxPlusLinear.layer,
          value: property.floor,
          label: 'קומה',
        ),
      if (property.entryDate.isNotEmpty)
        _FactDetailItem(
          icon: IconsaxPlusLinear.calendar,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(icon, color: const Color(0xFF13BEC9), size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        child,
        const SizedBox(height: 18),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
      ],
    );
  }
}

IconData _getFeatureIcon(String feature) {
  final f = feature.toLowerCase();
  if (f.contains('חני') || f.contains('חניה')) return IconsaxPlusLinear.car;
  if (f.contains('מעלי') || f.contains('מעלית')) return Icons.elevator_outlined;
  if (f.contains('ממ"ד') || f.contains('ממד') || f.contains('מרחב מוגן'))
    return IconsaxPlusLinear.shield_security;
  if (f.contains('מרפס') || f.contains('מרפסת')) return Icons.balcony_outlined;
  if (f.contains('מיזוג') || f.contains('מזגן') || f.contains('ac'))
    return IconsaxPlusLinear.wind_2;
  if (f.contains('ריהוט') || f.contains('מרוהט') || f.contains('מרוהטת'))
    return IconsaxPlusLinear.lamp_1;
  if (f.contains('סורג')) return Icons.grid_3x3_outlined;
  if (f.contains('גינ') || f.contains('חצר'))
    return Icons.local_florist_outlined;
  if (f.contains('דוד')) return Icons.wb_sunny_outlined;
  if (f.contains('חיות') || f.contains('כלב') || f.contains('חתול'))
    return Icons.pets_outlined;
  if (f.contains('משופץ') || f.contains('חדש'))
    return IconsaxPlusLinear.magicpen;
  return IconsaxPlusLinear.tick_circle;
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
        final icon = _getFeatureIcon(f);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: const Color(0xFF13BEC9),
              ),
              const SizedBox(width: 8),
              Text(
                f,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
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
            icon: IconsaxPlusLinear.star,
            label: 'מצב הנכס',
            value: property.condition),
      if (property.totalFloors.isNotEmpty)
        _DetailItem(
            icon: IconsaxPlusLinear.layer,
            label: 'קומות בבניין',
            value: property.totalFloors),
    ];

    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          _SecondaryDetailRow(item: items[i]),
          if (i != items.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(
                  height: 1, color: Colors.white.withValues(alpha: 0.08)),
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
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(item.icon, size: 18, color: const Color(0xFF13BEC9)),
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
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.5),
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
                          child: const RentchIcon(IconsaxPlusLinear.building,
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
                      RentchIcon(IconsaxPlusLinear.export_2,
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
    final isProcessing = property.virtualTour?.isProcessing == true;
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.fromLTRB(
              20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            border: const Border(
              top: BorderSide(
                color: Color(0xFFE2E8F0),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onLike,
                  icon: const RentchIcon(IconsaxPlusLinear.heart, size: 18),
                  label: const Text('אהבתי',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
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
                  icon: const Icon(Icons.view_in_ar_rounded, size: 18),
                  label: Text(
                    hasVirtualTour
                        ? 'סיור תלת־ממדי'
                        : isProcessing
                            ? 'סריקה בהכנה'
                            : 'בקש סיור תלת־ממדי',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF13BEC9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
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

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.property,
    required this.tour,
    required this.hasVirtualTour,
    required this.onTourTap,
  });

  final RentalProperty property;
  final PropertyVirtualTour? tour;
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
                              ? IconsaxPlusLinear.tag
                              : IconsaxPlusLinear.key,
                          label: property.transactionLabel,
                        ),
                        if (property.propertyType.trim().isNotEmpty)
                          _MetaPill(
                            icon: IconsaxPlusLinear.building_4,
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
                        const RentchIcon(
                          IconsaxPlusLinear.location,
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
                          _tourTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _tourSubtitle,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const RentchIcon(
                    IconsaxPlusLinear.arrow_left_2,
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

  String get _tourTitle {
    if (tour?.isReady == true) return 'סיור תלת־ממדי זמין עכשיו';
    if (tour?.isProcessing == true) return 'סריקת 3D בעיבוד';
    if (property.videoUrls.isNotEmpty) return 'וידאו סיור זמין';
    return 'אין עדיין סריקת 3D לנכס הזה';
  }

  String get _tourSubtitle {
    if (tour?.isReady == true) return 'פתח סיור עצמי ועבור בין חללי הדירה';
    if (tour?.isProcessing == true) {
      final progress = tour?.processingProgress;
      return progress == null
          ? 'הסיור יופיע כאן כשהעיבוד יסתיים'
          : 'התקדמות עיבוד: $progress%';
    }
    if (property.videoUrls.isNotEmpty) {
      return 'צפה בוידאו של הדירה בלי להוריד מודל כבד';
    }
    return 'אפשר לפתוח בקשה לסריקה או לצפות במדיה הקיימת';
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
          icon: IconsaxPlusLinear.building,
          label: '${property.roomsLabel} חדרים',
        ),
        _FactChip(
          icon: IconsaxPlusLinear.maximize_3,
          label: '${property.sizeM2} מ"ר',
        ),
        if (property.floor.isNotEmpty)
          _FactChip(
            icon: IconsaxPlusLinear.layer,
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
    final tour = property.virtualTour;
    final hasSource = tour?.hasSourceCapture == true;
    final isProcessing = tour?.isProcessing == true;
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
          Text(
            isProcessing
                ? 'סריקת ה־3D עדיין בעיבוד'
                : hasSource
                    ? 'הסריקה נשמרה ומחכה לעיבוד'
                    : 'עדיין אין סיור תלת־ממדי לנכס הזה',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isProcessing
                ? _processingCopy(tour)
                : hasSource
                    ? 'בעל הדירה כבר צילם וידאו סריקה, אבל backend הסריקות עדיין לא מחובר לעיבוד בענן.'
                    : 'כדי לפתוח הליכה חופשית בתוך הדירה צריך שתהיה סריקה או וידאו ייעודי של הנכס. כרגע אפשר להמשיך דרך התמונות והמודעה המקורית.',
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
                  icon: const RentchIcon(IconsaxPlusLinear.close_circle),
                  label: const Text('סגור'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: property.url.trim().isEmpty
                      ? null
                      : () async {
                          Navigator.of(context).pop();
                          await launchUrl(
                            Uri.parse(property.url),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                  icon: const RentchIcon(IconsaxPlusLinear.export_2),
                  label: const Text('פתח מודעה'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _processingCopy(PropertyVirtualTour? tour) {
    final progress = tour?.processingProgress;
    if (progress != null) {
      return 'העיבוד בענן הגיע ל־$progress%. כשה־viewer יהיה מוכן, הכפתור יפתח סיור אינטראקטיבי.';
    }
    return 'העיבוד בענן פעיל. כשה־viewer יהיה מוכן, הכפתור יפתח סיור אינטראקטיבי בלי להוריד קובץ כבד מראש.';
  }
}

class _VirtualTourScreen extends StatelessWidget {
  const _VirtualTourScreen({required this.property});

  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    final tour = property.virtualTour;
    if (tour?.isReady == true) {
      return _InteractiveTourScreen(property: property, tour: tour!);
    }

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
                    icon: IconsaxPlusLinear.arrow_right,
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

class _InteractiveTourScreen extends StatelessWidget {
  const _InteractiveTourScreen({required this.property, required this.tour});

  final RentalProperty property;
  final PropertyVirtualTour tour;

  @override
  Widget build(BuildContext context) {
    final quality = tour.qualityScore == null
        ? null
        : (tour.qualityScore! * 100).clamp(0, 100).round();
    return Scaffold(
      backgroundColor: const Color(0xFF061C2D),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _FloatingNavBtn(
                    icon: IconsaxPlusLinear.arrow_right,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tour.format.trim().isEmpty
                          ? 'viewer'
                          : tour.format.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Center(
                child: Container(
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: const Icon(
                    Icons.view_in_ar_rounded,
                    color: Colors.white,
                    size: 58,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                property.address,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'הסיור האינטראקטיבי נטען רק כשפותחים אותו, כדי לשמור את האפליקציה קלה ומהירה.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DarkMetricChip(
                    icon: IconsaxPlusLinear.cloud,
                    label: tour.provider,
                  ),
                  if (quality != null)
                    _DarkMetricChip(
                      icon: IconsaxPlusLinear.star_1,
                      label: 'איכות $quality%',
                    ),
                  if (tour.downloadUrl.trim().isNotEmpty)
                    const _DarkMetricChip(
                      icon: IconsaxPlusLinear.document_cloud,
                      label: 'קובץ זמין',
                    ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openViewer(context, tour.viewerUrl),
                  icon: const RentchIcon(IconsaxPlusLinear.export_2),
                  label: const Text('פתח סיור אינטראקטיבי'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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

  Future<void> _openViewer(BuildContext context, String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return;
    final launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!launched) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _DarkMetricChip extends StatelessWidget {
  const _DarkMetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _PropertySignalStrip extends StatelessWidget {
  const _PropertySignalStrip({required this.property});

  final RentalProperty property;

  static bool shouldShow(BuildContext context, RentalProperty property) {
    final provider = context.read<DatingProvider>();
    final isGuest = provider.isGuestMode;
    final properties = provider.filteredProperties;
    final isFirst = isGuest && properties.isNotEmpty && property.id == properties.first.id;
    final isSecond = isGuest && properties.length > 1 && property.id == properties[1].id;

    if (isFirst || isSecond) return true;

    final signals = property.marketSignals;
    return property.isVerifiedListing ||
        property.isNewListing ||
        signals.liveViewers > 0 ||
        signals.likesTodayFor(DateTime.now()) > 0;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DatingProvider>();
    final isGuest = provider.isGuestMode;
    final properties = provider.filteredProperties;
    final isFirst = isGuest && properties.isNotEmpty && property.id == properties.first.id;
    final isSecond = isGuest && properties.length > 1 && property.id == properties[1].id;

    if (isFirst) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: const [
          _PropertySignalChip(
            icon: IconsaxPlusLinear.eye,
            label: '245 צפו',
            color: Color(0xFF22C55E),
          ),
          _PropertySignalChip(
            icon: IconsaxPlusLinear.heart,
            label: '84 אהבו',
            color: Color(0xFFFF5A67),
          ),
        ],
      );
    }

    if (isSecond) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: const [
          _PropertySignalChip(
            icon: Icons.flash_on_rounded,
            label: 'דירה חדשה!',
            color: Color(0xFFEF4444),
          ),
          _PropertySignalChip(
            icon: IconsaxPlusLinear.heart,
            label: '47 אהבו',
            color: Color(0xFFFF5A67),
          ),
          _PropertySignalChip(
            icon: IconsaxPlusLinear.people,
            label: '3 צופים עכשיו',
            color: Color(0xFF22C55E),
          ),
        ],
      );
    }

    final signals = property.marketSignals;
    final likesToday = signals.likesTodayFor(DateTime.now());

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (property.isVerifiedListing)
          const _PropertySignalChip(
            icon: IconsaxPlusLinear.verify,
            label: 'דירה מאומתת',
            color: Color(0xFF13BEC9),
          ),
        if (property.isNewListing)
          const _PropertySignalChip(
            icon: IconsaxPlusLinear.flash_1,
            label: 'חדש · היה מהראשונים',
            color: Color(0xFF13BEC9),
          ),
        if (signals.liveViewers > 0)
          _PropertySignalChip(
            icon: IconsaxPlusLinear.eye,
            label: signals.liveViewers == 1
                ? 'מסתכל עכשיו'
                : '${signals.liveViewers} מסתכלים עכשיו',
            color: const Color(0xFF22C55E),
          ),
        if (likesToday > 0)
          _PropertySignalChip(
            icon: IconsaxPlusLinear.heart,
            label: '$likesToday אהבו היום',
            color: const Color(0xFFFF5A67),
          ),
      ],
    );
  }
}

class _PropertySignalChip extends StatelessWidget {
  const _PropertySignalChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RentchIcon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PropertyFactsCard extends StatelessWidget {
  final RentalProperty property;

  _PropertyFactsCard(this.property, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hasParking =
        property.features.any((f) => f.contains('חני') || f.contains('חניה'));
    final hasElevator =
        property.features.any((f) => f.contains('מעלי') || f.contains('מעלית'));

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _FactItemCard(
                IconsaxPlusLinear.building,
                property.roomsLabel,
                'חדרים',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FactItemCard(
                IconsaxPlusLinear.maximize_3,
                '${property.sizeM2}',
                'שטח במ"ר',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FactItemCard(
                IconsaxPlusLinear.layer,
                property.floor.isNotEmpty ? property.floor : '-',
                'קומה',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _FactItemCard(
                IconsaxPlusLinear.magicpen,
                property.condition.isNotEmpty ? property.condition : 'רגיל',
                'מצב הנכס',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: _FactItemCard(
                IconsaxPlusLinear.car,
                hasParking ? 'יש' : 'אין',
                'חנייה',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: _FactItemCard(
                Icons.elevator_outlined,
                hasElevator ? 'יש' : 'אין',
                'מעלית',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FactItemCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  _FactItemCard(this.icon, this.value, this.label, {Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF64748B)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _HorizontalReviewsList extends StatelessWidget {
  final List<AppReview> reviews;

  _HorizontalReviewsList(this.reviews, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: reviews.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final review = reviews[index];
          final initial = review.authorName.isNotEmpty
              ? review.authorName[0].toUpperCase()
              : '?';
          return Container(
            width: 290,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFFE2E8F0),
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            review.authorName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Text(
                            'שוכר לשעבר',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF08A).withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const RentchIcon(
                            IconsaxPlusLinear.star_1,
                            size: 12,
                            color: Color(0xFFCA8A04),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            review.rating.toString(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF854D0E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Text(
                    review.text,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: Color(0xFF475569),
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
