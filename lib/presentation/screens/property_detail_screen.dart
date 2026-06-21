import 'dart:async';
import 'dart:ui';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/matching/match_models.dart';
import 'package:dating_app/data/models/broker_design_models.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/widgets/property_share_sheet.dart';
import 'package:dating_app/presentation/widgets/safe_image.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:dating_app/presentation/widgets/scale_bounce.dart';
import 'package:dating_app/presentation/widgets/pulse_widget.dart';
import 'package:dating_app/presentation/widgets/fade_slide_entrance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:dating_app/presentation/screens/add_property_screen.dart' show EditPropertyScreen;
import 'package:url_launcher/url_launcher.dart';
import 'package:dating_app/presentation/widgets/animations/micro_animations.dart';

class PropertyDetailScreen extends StatefulWidget {
  const PropertyDetailScreen({
    super.key,
    required this.property,
    this.isLandlordPreview = false,
  });
  final RentalProperty property;
  final bool isLandlordPreview;

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
    if (!widget.isLandlordPreview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final provider = context.read<DatingProvider>();
        _analyticsProvider = provider;
        provider.beginPropertyDetailView(widget.property.id);
        // Record a real (distinct) view + pull live view/like counts.
        provider.recordPropertyView(widget.property.id);
        // If this listing's 3D tour is still "processing", re-check Teleport now
        // so a finished/failed capture stops showing "בעיבוד" indefinitely.
        provider.refreshPropertyTour(widget.property.id);
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Landlord previewing their own listing — refresh the tour state too.
        context.read<DatingProvider>().refreshPropertyTour(widget.property.id);
      });
    }
  }

  @override
  void dispose() {
    if (!widget.isLandlordPreview) {
      unawaited(
        _analyticsProvider?.endPropertyDetailView(widget.property.id) ??
            Future<void>.value(),
      );
    }
    _pageController.dispose();
    super.dispose();
  }

  void _handleGalleryPageChanged(String propertyId, int index) {
    setState(() => _currentPage = index);
    if (!widget.isLandlordPreview) {
      context.read<DatingProvider>().recordPropertyGallerySwipe(
            propertyId,
            index,
          );
    }
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
        // Per-property design (chosen during listing creation) takes precedence
        // over user-level broker branding, and applies for ANY viewer (not just owner).
        final propertyBranding = p.hasCustomDesign
            ? BrokerBrandingConfig.fromJson({
                'propertyTemplate': p.designTemplate,
                if (p.designAccent != 0) ...{
                  'accentColorValue': p.designAccent,
                  'primaryColorValue': p.designAccent,
                },
              })
            : null;
        final branding = propertyBranding ?? provider.brokerBranding;
        // Use property template if it exists (any viewer), OR if viewer is broker with custom branding
        final useTemplate = propertyBranding != null ||
            (provider.isBroker &&
                provider.brokerBranding.propertyTemplate !=
                    BrokerPropertyTemplate.rentlyClassic);

        // Always show template if property has custom design (applies to all viewers)
        if (p.hasCustomDesign ||
            (useTemplate && branding.propertyTemplate != BrokerPropertyTemplate.rentlyClassic)) {
          return _BrokerPropertyDetailTemplate(
            property: p,
            branding: branding,
            controller: _pageController,
            currentPage: _currentPage,
            onPageChanged: (i) => _handleGalleryPageChanged(p.id, i),
            reviews: reviews,
            avgRating: avgRating,
            hasVirtualTour: hasVirtualTour,
            isLandlordPreview: widget.isLandlordPreview,
            onBackTap: () => Navigator.of(context).pop(),
            onShareTap: () => showPropertyShareSheet(context, p),
            onLike: () {
              context.read<DatingProvider>().likeProperty(p.id);
              Navigator.of(context).pop();
            },
            onTour: () => openPropertyTour(context, p),
            onEdit: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EditPropertyScreen(property: p),
              ),
            ),
          );
        }

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
                                        const RentlyIcon(
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
                            FadeSlideEntrance(
                              duration: const Duration(milliseconds: 450),
                              offset: const Offset(0.0, 30.0),
                              child: SizedBox(
                                height: 105,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: media.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 12),
                                  itemBuilder: (context, index) {
                                    final item = media[index];
                                    return ScaleBounce(
                                      onTap: () {
                                        _pageController.animateToPage(
                                          index,
                                          duration:
                                              const Duration(milliseconds: 300),
                                          curve: Curves.easeInOut,
                                        );
                                      },
                                      scaleDownTo: 0.90,
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
                          if (!widget.isLandlordPreview)
                            _SectionCardShell(
                              title: 'למה ההתאמה הזו',
                              icon: IconsaxPlusLinear.flash_1,
                              child: _MatchInsightCard(property: p),
                            ),

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
                child: ScaleBounce(
                  onTap: () => showPropertyShareSheet(context, p),
                  scaleDownTo: 0.88,
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
                    child: const Center(
                      child: RentlyIcon(
                        IconsaxPlusLinear.export_2,
                        color: Colors.black,
                        size: 24,
                      ),
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
                  isLandlordPreview: widget.isLandlordPreview,
                  onLike: () {
                    context.read<DatingProvider>().likeProperty(p.id);
                    Navigator.of(context).pop();
                  },
                  onTour: () => openPropertyTour(context, p),
                  onEdit: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EditPropertyScreen(property: p),
                    ),
                  ),
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
              ScaleBounce(
                onTap: onBackTap,
                scaleDownTo: 0.88,
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
                  child: const RentlyIcon(
                    IconsaxPlusLinear.arrow_right_3,
                    color: Color(0xFF0F172A),
                    size: 20,
                  ),
                ),
              ),
              // Share Button (Mockup style circular white)
              ScaleBounce(
                onTap: onShareTap,
                scaleDownTo: 0.88,
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
                  child: const RentlyIcon(
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

class _BrokerPropertyDetailTemplate extends StatelessWidget {
  const _BrokerPropertyDetailTemplate({
    required this.property,
    required this.branding,
    required this.controller,
    required this.currentPage,
    required this.onPageChanged,
    required this.reviews,
    required this.avgRating,
    required this.hasVirtualTour,
    required this.isLandlordPreview,
    required this.onBackTap,
    required this.onShareTap,
    required this.onLike,
    required this.onTour,
    required this.onEdit,
  });

  final RentalProperty property;
  final BrokerBrandingConfig branding;
  final PageController controller;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final List<AppReview> reviews;
  final double avgRating;
  final bool hasVirtualTour;
  final bool isLandlordPreview;
  final VoidCallback onBackTap;
  final VoidCallback onShareTap;
  final VoidCallback onLike;
  final VoidCallback onTour;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final content = switch (branding.propertyTemplate) {
      BrokerPropertyTemplate.acidHero => _buildAcidHero(context),
      BrokerPropertyTemplate.dashboardGlass => _buildDashboardGlass(context),
      BrokerPropertyTemplate.estateCard => _buildEstateCard(context),
      BrokerPropertyTemplate.galleryEditorial => _buildGalleryEditorial(context),
      BrokerPropertyTemplate.cinematicGlass => _buildCinematicGlass(context),
      BrokerPropertyTemplate.rentlyClassic => _buildGalleryEditorial(context),
    };

    return Scaffold(
      backgroundColor: _pageBackground,
      body: Stack(
        children: [
          content,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomBar(
              property: property,
              hasVirtualTour: hasVirtualTour,
              isLandlordPreview: isLandlordPreview,
              onLike: onLike,
              onTour: onTour,
              onEdit: onEdit,
            ),
          ),
        ],
      ),
    );
  }

  Color get _pageBackground => switch (branding.propertyTemplate) {
        BrokerPropertyTemplate.acidHero => Color.alphaBlend(
            branding.accentColor.withValues(alpha: 0.18),
            const Color(0xFFF7FAF2),
          ),
        BrokerPropertyTemplate.dashboardGlass => const Color(0xFFEAF2F0),
        BrokerPropertyTemplate.estateCard => const Color(0xFFF5F6F8),
        BrokerPropertyTemplate.galleryEditorial => Colors.white,
        BrokerPropertyTemplate.cinematicGlass => branding.secondaryColor,
        BrokerPropertyTemplate.rentlyClassic => Colors.white,
      };

  Widget _buildAcidHero(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              22,
              MediaQuery.of(context).padding.top + 14,
              22,
              124,
            ),
            child: Column(
              children: [
                _TemplateTopBar(
                  branding: branding,
                  title: property.ownerName,
                  dark: false,
                  onBackTap: onBackTap,
                  onShareTap: onShareTap,
                ),
                const SizedBox(height: 14),
                Text(
                  property.address,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: branding.secondaryColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${property.city} · ${property.transactionLabel}',
                  style: TextStyle(
                    color: branding.secondaryColor.withValues(alpha: 0.68),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _TemplateHeroMedia(
                  property: property,
                  controller: controller,
                  currentPage: currentPage,
                  onPageChanged: onPageChanged,
                  height: 320,
                  radius: 34,
                  overlay: _AcidHeroOverlay(
                    property: property,
                    branding: branding,
                    avgRating: avgRating,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _GlassFilterPill(
                        icon: IconsaxPlusLinear.layer,
                        label: property.floor.isEmpty
                            ? property.propertyType
                            : 'קומה ${property.floor}',
                        branding: branding,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _RoundTemplateButton(
                      icon: IconsaxPlusLinear.location,
                      onTap: () {},
                      color: branding.secondaryColor,
                    ),
                    const SizedBox(width: 10),
                    _RoundTemplateButton(
                      icon: IconsaxPlusLinear.export_2,
                      onTap: onShareTap,
                      color: branding.secondaryColor,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _AcidPriceCard(property: property, branding: branding),
                const SizedBox(height: 18),
                _TemplateFactsWrap(property: property, branding: branding),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardGlass(BuildContext context) {
    final signals = property.marketSignals;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              MediaQuery.of(context).padding.top + 12,
              18,
              124,
            ),
            child: Transform.rotate(
              angle: -0.018,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.64),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
                ),
                child: Transform.rotate(
                  angle: 0.018,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TemplateTopBar(
                        branding: branding,
                        title: '',
                        dark: false,
                        onBackTap: onBackTap,
                        onShareTap: onShareTap,
                      ),
                      const SizedBox(height: 18),
                      _TemplateHeroMedia(
                        property: property,
                        controller: controller,
                        currentPage: currentPage,
                        onPageChanged: onPageChanged,
                        height: 250,
                        radius: 18,
                      ),
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              property.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: branding.secondaryColor,
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                                height: 1.04,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _RoundTemplateButton(
                            icon: IconsaxPlusLinear.heart,
                            onTap: onLike,
                            color: branding.primaryColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${property.priceLabel} · ${property.priceSuffixLabel}',
                        style: TextStyle(
                          color: branding.secondaryColor.withValues(alpha: 0.58),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _MarketMetricCard(
                              icon: IconsaxPlusLinear.eye,
                              label: 'צפיות',
                              value: _compactNumber(
                                signals.views + signals.detailViews,
                              ),
                              branding: branding,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _MarketMetricCard(
                              icon: IconsaxPlusLinear.heart,
                              label: 'שמירות',
                              value: _compactNumber(signals.saves),
                              branding: branding,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _TemplateFactsWrap(property: property, branding: branding),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEstateCard(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              0,
              MediaQuery.of(context).padding.top,
              0,
              120,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 510,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _TemplateHeroMedia(
                          property: property,
                          controller: controller,
                          currentPage: currentPage,
                          onPageChanged: onPageChanged,
                          height: 510,
                          radius: 0,
                          alignment: Alignment.center,
                        ),
                      ),
                      Positioned(
                        top: 18,
                        left: 20,
                        right: 20,
                        child: _TemplateTopBar(
                          branding: branding,
                          title: '',
                          dark: true,
                          onBackTap: onBackTap,
                          onShareTap: onShareTap,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(32),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      property.priceLabel,
                                      style: TextStyle(
                                        color: branding.secondaryColor,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  if (property.isNewListing)
                                    _StatusCapsule(
                                      label: 'חדש',
                                      fg: branding.primaryColor,
                                      bg: branding.primaryColor
                                          .withValues(alpha: 0.10),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(
                                    IconsaxPlusLinear.location,
                                    size: 16,
                                    color: branding.primaryColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      property.address,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              _TemplateFactsWrap(
                                property: property,
                                branding: branding,
                                dense: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (reviews.isNotEmpty) ...[
                        _ReviewsPreviewSection(reviews: reviews),
                        const SizedBox(height: 22),
                      ],
                      _FeatureWrap(features: property.features.take(8).toList()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGalleryEditorial(BuildContext context) {
    final images = property.media;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              0,
              MediaQuery.of(context).padding.top,
              0,
              124,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 385,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _TemplateHeroMedia(
                          property: property,
                          controller: controller,
                          currentPage: currentPage,
                          onPageChanged: onPageChanged,
                          height: 385,
                          radius: 0,
                        ),
                      ),
                      Positioned(
                        top: 18,
                        left: 20,
                        right: 20,
                        child: _TemplateTopBar(
                          branding: branding,
                          title: '',
                          dark: true,
                          onBackTap: onBackTap,
                          onShareTap: onShareTap,
                        ),
                      ),
                    ],
                  ),
                ),
                if (images.length > 1)
                  SizedBox(
                    height: 92,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                      scrollDirection: Axis.horizontal,
                      itemCount: images.length.clamp(0, 5).toInt(),
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, index) => GestureDetector(
                        onTap: () => controller.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOut,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: SizedBox(
                            width: 94,
                            height: 66,
                            child: SafeMedia(
                              media: images[index],
                              fit: BoxFit.cover,
                              fallback: _ImageFallback(city: property.city),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              property.street.isNotEmpty
                                  ? '${property.propertyType} ב${property.street}'
                                  : property.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: branding.secondaryColor,
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                                height: 1.08,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: onShareTap,
                            icon: const RentlyIcon(IconsaxPlusLinear.export_2),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _StatusCapsule(
                        label: property.transactionLabel,
                        fg: branding.secondaryColor,
                        bg: const Color(0xFFF3F4F6),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${property.priceLabel}${property.transactionType == PropertyTransactionType.rent ? '/חודש' : ''}',
                              style: TextStyle(
                                color: branding.secondaryColor,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          FilledButton(
                            onPressed: onTour,
                            style: FilledButton.styleFrom(
                              backgroundColor: branding.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text(
                              'Book Now',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'About this Home',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _propertyDescription,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCinematicGlass(BuildContext context) {
    final darkText = Colors.white.withValues(alpha: 0.84);
    return Stack(
      children: [
        Positioned.fill(
          child: SafeMedia(
            media: property.primaryMedia ??
                const PropertyMedia(url: '', type: PropertyMediaType.image),
            fit: BoxFit.cover,
            alignment: Alignment.center,
            fallback: _ImageFallback(city: property.city),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.30),
                  branding.secondaryColor.withValues(alpha: 0.52),
                  branding.secondaryColor.withValues(alpha: 0.90),
                ],
              ),
            ),
          ),
        ),
        CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  MediaQuery.of(context).padding.top + 14,
                  18,
                  126,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TemplateTopBar(
                      branding: branding,
                      title: 'Details',
                      dark: true,
                      onBackTap: onBackTap,
                      onShareTap: onShareTap,
                    ),
                    SizedBox(height: MediaQuery.sizeOf(context).height * 0.42),
                    if (property.media.length > 1)
                      SizedBox(
                        height: 82,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: property.media.length.clamp(0, 3).toInt(),
                          separatorBuilder: (_, __) => const SizedBox(width: 10),
                          itemBuilder: (_, index) => ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 124,
                              child: SafeMedia(
                                media: property.media[index],
                                fit: BoxFit.cover,
                                fallback: _ImageFallback(city: property.city),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Previews',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: List.generate(
                                        5,
                                        (index) => const Padding(
                                          padding: EdgeInsets.only(left: 3),
                                          child: Icon(
                                            IconsaxPlusLinear.star_1,
                                            color: Color(0xFFFFC233),
                                            size: 15,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _StatusCapsule(
                                label: property.priceLabel,
                                fg: branding.secondaryColor,
                                bg: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      property.address,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _propertyDescription,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: darkText,
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String get _propertyDescription {
    final featureText = property.features.take(3).join(', ');
    final base =
        '${property.propertyType} ${property.transactionLabel} ב${property.city}, ${property.roomsLabel} חדרים ו-${property.sizeM2} מ"ר';
    if (featureText.isEmpty) return base;
    return '$base. כולל $featureText.';
  }
}

class _TemplateHeroMedia extends StatelessWidget {
  const _TemplateHeroMedia({
    required this.property,
    required this.controller,
    required this.currentPage,
    required this.onPageChanged,
    required this.height,
    required this.radius,
    this.overlay,
    this.alignment = Alignment.topCenter,
  });

  final RentalProperty property;
  final PageController controller;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final double height;
  final double radius;
  final Widget? overlay;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final media = property.media;
    final safeCurrent =
        media.isEmpty ? 0 : currentPage.clamp(0, media.length - 1).toInt();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            media.isEmpty
                ? _ImageFallback(city: property.city)
                : PageView.builder(
                    controller: controller,
                    onPageChanged: onPageChanged,
                    itemCount: media.length,
                    itemBuilder: (_, index) => SafeMedia(
                      media: media[index],
                      fit: BoxFit.cover,
                      alignment: alignment,
                      fallback: _ImageFallback(city: property.city),
                      videoMode: SafeVideoDisplayMode.playback,
                    ),
                  ),
            if (overlay != null) overlay!,
            if (media.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: _CarouselDots(count: media.length, current: safeCurrent),
              ),
          ],
        ),
      ),
    );
  }
}

class _TemplateTopBar extends StatelessWidget {
  const _TemplateTopBar({
    required this.branding,
    required this.title,
    required this.dark,
    required this.onBackTap,
    required this.onShareTap,
  });

  final BrokerBrandingConfig branding;
  final String title;
  final bool dark;
  final VoidCallback onBackTap;
  final VoidCallback onShareTap;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : branding.secondaryColor;
    return Row(
      children: [
        _RoundTemplateButton(
          icon: IconsaxPlusLinear.arrow_right,
          onTap: onBackTap,
          color: fg,
          translucent: dark,
        ),
        Expanded(
          child: Center(
            child: title.isEmpty
                ? _BrandLogoMark(branding: branding, compact: true)
                : Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
        ),
        _RoundTemplateButton(
          icon: IconsaxPlusLinear.export_2,
          onTap: onShareTap,
          color: fg,
          translucent: dark,
        ),
      ],
    );
  }
}

class _RoundTemplateButton extends StatelessWidget {
  const _RoundTemplateButton({
    required this.icon,
    required this.onTap,
    required this.color,
    this.translucent = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final bool translucent;

  @override
  Widget build(BuildContext context) {
    return ScaleBounce(
      onTap: onTap,
      scaleDownTo: 0.88,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: translucent ? 14 : 0,
            sigmaY: translucent ? 14 : 0,
          ),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: translucent
                  ? Colors.white.withValues(alpha: 0.20)
                  : Colors.white.withValues(alpha: 0.82),
              shape: BoxShape.circle,
              border: Border.all(
                color: translucent
                    ? Colors.white.withValues(alpha: 0.24)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
        ),
      ),
    );
  }
}

class _BrandLogoMark extends StatelessWidget {
  const _BrandLogoMark({
    required this.branding,
    this.compact = false,
  });

  final BrokerBrandingConfig branding;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 42.0 : 58.0;
    final fallback = Container(
      color: Colors.white,
      child: Icon(
        Icons.business_rounded,
        color: branding.primaryColor,
        size: compact ? 19 : 25,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.36),
      child: SizedBox(
        width: size,
        height: size,
        child: branding.hasLogo
            ? SafeImage(source: branding.logoPath, fallback: fallback)
            : fallback,
      ),
    );
  }
}

class _AcidHeroOverlay extends StatelessWidget {
  const _AcidHeroOverlay({
    required this.property,
    required this.branding,
    required this.avgRating,
  });

  final RentalProperty property;
  final BrokerBrandingConfig branding;
  final double avgRating;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          bottom: 22,
          right: 22,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 11, 16, 11),
                decoration: BoxDecoration(
                  color: branding.secondaryColor.withValues(alpha: 0.46),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: branding.accentColor,
                      child: Text(
                        property.ownerName.isEmpty ? '?' : property.ownerName[0],
                        style: TextStyle(
                          color: branding.secondaryColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          property.ownerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          avgRating > 0
                              ? '${avgRating.toStringAsFixed(1)} דירוג'
                              : 'מתווך נדל״ן',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 22,
          left: 22,
          child: Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: branding.secondaryColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Center(
              child: Text(
                '${property.sizeM2}\nמ״ר',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: branding.accentColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassFilterPill extends StatelessWidget {
  const _GlassFilterPill({
    required this.icon,
    required this.label,
    required this.branding,
  });

  final IconData icon;
  final String label;
  final BrokerBrandingConfig branding;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: branding.secondaryColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: branding.secondaryColor,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AcidPriceCard extends StatelessWidget {
  const _AcidPriceCard({
    required this.property,
    required this.branding,
  });

  final RentalProperty property;
  final BrokerBrandingConfig branding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            property.propertyType,
            style: TextStyle(
              color: branding.secondaryColor,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                property.priceLabel,
                style: TextStyle(
                  color: branding.secondaryColor,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  property.priceSuffixLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TemplateFactsWrap extends StatelessWidget {
  const _TemplateFactsWrap({
    required this.property,
    required this.branding,
    this.dense = false,
  });

  final RentalProperty property;
  final BrokerBrandingConfig branding;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final facts = [
      _TemplateFact(IconsaxPlusLinear.building, '${property.roomsLabel} חדרים'),
      _TemplateFact(IconsaxPlusLinear.maximize_3, '${property.sizeM2} מ״ר'),
      if (property.floor.isNotEmpty)
        _TemplateFact(IconsaxPlusLinear.layer, 'קומה ${property.floor}'),
      if (property.condition.isNotEmpty)
        _TemplateFact(IconsaxPlusLinear.star, property.condition),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: facts
          .map(
            (fact) => Container(
              padding: EdgeInsets.symmetric(
                horizontal: dense ? 12 : 15,
                vertical: dense ? 9 : 12,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(fact.icon, size: 16, color: branding.primaryColor),
                  const SizedBox(width: 7),
                  Text(
                    fact.label,
                    style: TextStyle(
                      color: branding.secondaryColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _TemplateFact {
  const _TemplateFact(this.icon, this.label);
  final IconData icon;
  final String label;
}

class _MarketMetricCard extends StatelessWidget {
  const _MarketMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.branding,
  });

  final IconData icon;
  final String label;
  final String value;
  final BrokerBrandingConfig branding;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 126,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.64)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: branding.secondaryColor.withValues(alpha: 0.48)),
          const Spacer(),
          Text(
            label,
            style: TextStyle(
              color: branding.secondaryColor.withValues(alpha: 0.65),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: branding.secondaryColor,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 0.95,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCapsule extends StatelessWidget {
  const _StatusCapsule({
    required this.label,
    required this.fg,
    required this.bg,
  });

  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ReviewsPreviewSection extends StatelessWidget {
  const _ReviewsPreviewSection({required this.reviews});

  final List<AppReview> reviews;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reviews',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: reviews.length.clamp(0, 4).toInt(),
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, index) => SizedBox(
              width: 230,
              child: _ReviewTile(review: reviews[index]),
            ),
          ),
        ),
      ],
    );
  }
}

String _compactNumber(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value.toString();
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
        return AnimatedScale(
          scale: active ? 1.35 : 1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: active ? 20 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primary
                  : Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(4),
            ),
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
            const RentlyIcon(IconsaxPlusLinear.building,
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
                            child: const RentlyIcon(
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
                          const RentlyIcon(
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
                        const RentlyIcon(IconsaxPlusLinear.profile_circle,
                            size: 16, color: Color(0xFF13BEC9)),
                        const SizedBox(width: 6),
                        const Text(
                          'פרופיל משכיר',
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
                  const RentlyIcon(
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
                            const RentlyIcon(IconsaxPlusLinear.star_1,
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
        return ScaleBounce(
          onTap: () {},
          scaleDownTo: 0.94,
          child: Container(
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
                          child: const RentlyIcon(IconsaxPlusLinear.building,
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
                      RentlyIcon(IconsaxPlusLinear.export_2,
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
    this.isLandlordPreview = false,
    this.onEdit,
  });
  final RentalProperty property;
  final bool hasVirtualTour;
  final VoidCallback onLike;
  final VoidCallback onTour;
  final bool isLandlordPreview;
  final VoidCallback? onEdit;

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
                child: ScaleBounce(
                  onTap: isLandlordPreview ? onEdit : onLike,
                  scaleDownTo: 0.94,
                  child: isLandlordPreview
                      ? OutlinedButton.icon(
                          onPressed: onEdit,
                          icon: const RentlyIcon(IconsaxPlusLinear.edit, size: 18),
                          label: const Text('עריכת נכס',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0F172A),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: onLike,
                          icon: const RentlyIcon(IconsaxPlusLinear.heart, size: 18),
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
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: PulseWidget(
                  scaleUpTo: 1.05,
                  duration: const Duration(milliseconds: 1600),
                  child: ScaleBounce(
                    onTap: onTour,
                    scaleDownTo: 0.95,
                    child: ShineDecorator(
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
                        RentlyIcon(
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
                  const RentlyIcon(
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
    final hasFailed = tour?.hasFailed == true;
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
              color: hasFailed
                  ? AppColors.coral.withValues(alpha: 0.12)
                  : AppColors.primaryLight2,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              hasFailed
                  ? Icons.error_outline_rounded
                  : Icons.view_in_ar_rounded,
              color: hasFailed ? AppColors.coral : AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            hasFailed
                ? 'הסריקה התלת־ממדית נכשלה'
                : isProcessing
                    ? 'סריקת ה־3D בעיבוד'
                    : hasSource
                        ? 'הסריקה בתור לעיבוד'
                        : 'עדיין אין סיור תלת־ממדי לנכס הזה',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasFailed
                ? 'העיבוד לא הצליח לשחזר את הדירה מהסרטון. לרוב זה קורה כשהצילום מהיר מדי או חלקי. צלמו שוב לאט, סובבו סביב כל חדר וודאו תאורה טובה — ונסו להעלות מחדש.'
                : isProcessing
                    ? _processingCopy(tour)
                    : hasSource
                        ? 'בעל הדירה צילם את הדירה וממתין שהעיבוד יתחיל. הסיור יהיה זמין בקרוב.'
                        : 'כדי לפתוח הליכה חופשית בתוך הדירה צריך שתהיה סריקה או וידאו ייעודי של הנכס. כרגע אפשר להמשיך דרך התמונות והמודעה המקורית.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.55,
            ),
          ),
          if (isProcessing) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 6,
                backgroundColor: AppColors.primaryLight2,
                color: AppColors.primary,
                value: tour?.processingProgress != null
                    ? (tour!.processingProgress! / 100.0)
                    : null,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _processingEta(tour),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const RentlyIcon(IconsaxPlusLinear.close_circle),
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
                  icon: const RentlyIcon(IconsaxPlusLinear.export_2),
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
    final stage = tour?.processingStage.trim().toLowerCase() ?? '';
    final progress = tour?.processingProgress;
    if (progress != null) {
      return 'שלב עיבוד: $progress% הושלם. כשיהיה מוכן, הכפתור יפתח סיור אינטראקטיבי.';
    }
    return switch (stage) {
      'pending' => 'הסריקה ממתינה לתור בשרת. בדרך כלל מתחיל תוך דקה.',
      'staging' => 'מנתח את חללי הדירה ובונה את סביבת ה־3D. עוד כמה דקות.',
      'complete' => 'העיבוד הסתיים, ה־viewer מוכן לפתיחה.',
      _ => 'העיבוד בענן פעיל. כשה־viewer יהיה מוכן, הכפתור יפתח סיור אינטראקטיבי.',
    };
  }

  String _processingEta(PropertyVirtualTour? tour) {
    final stage = tour?.processingStage.trim().toLowerCase() ?? '';
    return switch (stage) {
      'pending' => 'זמן משוער: 1–3 דקות',
      'staging' => 'זמן משוער: 2–5 דקות',
      _ => 'זמן משוער: כמה דקות',
    };
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

  // Luma virtual-staging returns an AI image, not an interactive 3D asset.
  // Detect that so we render it inline as a visualization instead of the
  // "interactive tour" placeholder (which is meant for video/real-3D viewers).
  bool get _isImageVisualization {
    final f = tour.format.trim().toLowerCase();
    if (f == 'image') return true;
    if (f == 'video' || f == 'glb' || f == 'gltf' || f == 'usdz' ||
        f == 'splat' || f == 'mesh' || f == '3d') {
      return false;
    }
    final u = (tour.previewImageUrl.trim().isNotEmpty
            ? tour.previewImageUrl
            : tour.viewerUrl)
        .trim()
        .toLowerCase()
        .split('?')
        .first;
    return u.endsWith('.png') ||
        u.endsWith('.jpg') ||
        u.endsWith('.jpeg') ||
        u.endsWith('.webp');
  }

  @override
  Widget build(BuildContext context) {
    if (_isImageVisualization) return _buildImageVisualization(context);
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
                  icon: const RentlyIcon(IconsaxPlusLinear.export_2),
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

  // Renders the AI-staged image inline (pinch-to-zoom), with explicit
  // loading/error states. Used for Luma "הדמיה" results so the user sees the
  // visualization in-app rather than a 3D-tour placeholder + external browser.
  Widget _buildImageVisualization(BuildContext context) {
    final url = tour.previewImageUrl.trim().isNotEmpty
        ? tour.previewImageUrl.trim()
        : tour.viewerUrl.trim();
    return Scaffold(
      backgroundColor: const Color(0xFF061C2D),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: url.isEmpty
                  ? const Center(
                      child: Icon(Icons.broken_image_rounded,
                          color: Colors.white38, size: 54),
                    )
                  : InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Center(
                        child: Image.network(
                          url,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.6, color: Colors.white),
                            );
                          },
                          errorBuilder: (_, __, ___) => const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image_rounded,
                                    color: Colors.white38, size: 54),
                                SizedBox(height: 10),
                                Text('לא ניתן לטעון את ההדמיה',
                                    style: TextStyle(color: Colors.white60)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            Positioned(
              top: 12,
              left: 18,
              right: 18,
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
                      color: AppColors.primary.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            size: 16, color: Colors.white),
                        SizedBox(width: 8),
                        Text('הדמיית AI',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12)),
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
    final signals = property.marketSignals;
    return property.isVerifiedListing ||
        property.isNewListing ||
        signals.views > 0 ||
        signals.likes > 0 ||
        signals.liveViewers > 0 ||
        signals.likesTodayFor(DateTime.now()) > 0;
  }

  @override
  Widget build(BuildContext context) {
    // Watch so the strip refreshes when real view/like counts arrive.
    context.watch<DatingProvider>();
    final signals = property.marketSignals;
    final likesToday = signals.likesTodayFor(DateTime.now());

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (signals.views > 0)
          _PropertySignalChip(
            icon: IconsaxPlusLinear.eye,
            label: '${signals.views} צפו',
            color: const Color(0xFF22C55E),
          ),
        if (signals.likes > 0)
          _PropertySignalChip(
            icon: IconsaxPlusLinear.heart,
            label: '${signals.likes} אהבו',
            color: const Color(0xFFFF5A67),
          ),
        if (property.isVerifiedListing)
          const _PropertySignalChip(
            icon: IconsaxPlusLinear.verify,
            label: 'דירה מאומתת',
            color: Color(0xFF13BEC9),
          ),
        if (property.isNewListing)
          const SignalStripPulse(
            child: _PropertySignalChip(
              icon: IconsaxPlusLinear.flash_1,
              label: 'דירה הועלתה לאחרונה',
              color: Color(0xFF13BEC9),
            ),
          ),
        if (signals.liveViewers > 0)
          SignalStripPulse(
            child: _PropertySignalChip(
              icon: IconsaxPlusLinear.eye,
              label: signals.liveViewers == 1
                  ? 'מסתכל עכשיו'
                  : '${signals.liveViewers} מסתכלים עכשיו',
              color: const Color(0xFF22C55E),
            ),
          ),
        if (likesToday > 0)
          SignalStripPulse(
            child: _PropertySignalChip(
              icon: IconsaxPlusLinear.heart,
              label: '$likesToday אהבו היום',
              color: const Color(0xFFFF5A67),
            ),
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
          RentlyIcon(icon, size: 15, color: color),
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
              child: FadeSlideEntrance(
                delay: Duration.zero,
                duration: const Duration(milliseconds: 400),
                offset: const Offset(0.0, 25.0),
                child: _FactItemCard(
                  IconsaxPlusLinear.building,
                  property.roomsLabel,
                  'חדרים',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FadeSlideEntrance(
                delay: const Duration(milliseconds: 60),
                duration: const Duration(milliseconds: 400),
                offset: const Offset(0.0, 25.0),
                child: _FactItemCard(
                  IconsaxPlusLinear.maximize_3,
                  '${property.sizeM2}',
                  'שטח במ"ר',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FadeSlideEntrance(
                delay: const Duration(milliseconds: 120),
                duration: const Duration(milliseconds: 400),
                offset: const Offset(0.0, 25.0),
                child: _FactItemCard(
                  IconsaxPlusLinear.layer,
                  property.floor.isNotEmpty ? property.floor : '-',
                  'קומה',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: FadeSlideEntrance(
                delay: const Duration(milliseconds: 180),
                duration: const Duration(milliseconds: 400),
                offset: const Offset(0.0, 25.0),
                child: _FactItemCard(
                  IconsaxPlusLinear.magicpen,
                  property.condition.isNotEmpty ? property.condition : 'רגיל',
                  'מצב הנכס',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: FadeSlideEntrance(
                delay: const Duration(milliseconds: 240),
                duration: const Duration(milliseconds: 400),
                offset: const Offset(0.0, 25.0),
                child: _FactItemCard(
                  IconsaxPlusLinear.car,
                  hasParking ? 'יש' : 'אין',
                  'חנייה',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: FadeSlideEntrance(
                delay: const Duration(milliseconds: 300),
                duration: const Duration(milliseconds: 400),
                offset: const Offset(0.0, 25.0),
                child: _FactItemCard(
                  Icons.elevator_outlined,
                  hasElevator ? 'יש' : 'אין',
                  'מעלית',
                ),
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
                          const RentlyIcon(
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

// ─── Match insight ("why this match") ─────────────────────────────────────────

class _MatchInsightCard extends StatelessWidget {
  const _MatchInsightCard({required this.property});
  final RentalProperty property;

  (Color, Color) _tierColors(MatchTier tier) => switch (tier) {
        MatchTier.perfect => (const Color(0xFF16A34A), const Color(0xFFDCFCE7)),
        MatchTier.excellent => (AppColors.primary, AppColors.primaryLight2),
        MatchTier.good => (const Color(0xFF2563EB), const Color(0xFFDBEAFE)),
        MatchTier.fair => (const Color(0xFFD97706), const Color(0xFFFEF3C7)),
        MatchTier.weak => (AppColors.textSecondary, const Color(0xFFF1F5F9)),
      };

  IconData _reasonIcon(MatchReasonKind kind) => switch (kind) {
        MatchReasonKind.budget => IconsaxPlusLinear.money_recive,
        MatchReasonKind.location => IconsaxPlusLinear.location,
        MatchReasonKind.rooms => IconsaxPlusLinear.home_2,
        MatchReasonKind.size => IconsaxPlusLinear.maximize_3,
        MatchReasonKind.timing => IconsaxPlusLinear.calendar_1,
        MatchReasonKind.amenity => IconsaxPlusLinear.flash_1,
        MatchReasonKind.lifestyle => IconsaxPlusLinear.heart,
        MatchReasonKind.quality => IconsaxPlusLinear.verify,
        MatchReasonKind.mutualInterest => IconsaxPlusLinear.people,
        MatchReasonKind.dealBreaker => IconsaxPlusLinear.warning_2,
      };

  @override
  Widget build(BuildContext context) {
    final outcome = context.read<DatingProvider>().matchOutcome(property);
    final (fg, bg) = _tierColors(outcome.tier);
    final positives = outcome.positives.take(4).toList();
    final concerns = outcome.concerns.take(2).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Score + tier header
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Center(
                child: Text(
                  '${outcome.score}',
                  style: TextStyle(
                      color: fg, fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(outcome.tier.label,
                    style: TextStyle(
                        color: fg, fontWeight: FontWeight.w900, fontSize: 16)),
                Text(
                  outcome.hasTwoSidedSignal
                      ? 'דירוג הדדי — מתחשב גם בהעדפות בעל הדירה'
                      : 'לפי ההעדפות שלך',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (final r in positives)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_reasonIcon(r.kind),
                      size: 14, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(r.label,
                      style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600)),
                ),
                const Icon(Icons.check_circle_rounded,
                    size: 16, color: Color(0xFF16A34A)),
              ],
            ),
          ),
        for (final r in concerns)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.coral.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_reasonIcon(r.kind),
                      size: 14, color: AppColors.coral),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(r.label,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
