import 'dart:async';
import 'dart:ui';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/finance/affordability.dart';
import 'package:dating_app/core/matching/match_models.dart';
import 'package:dating_app/data/models/broker_design_models.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/core/services/event_service.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/widgets/ask_rently_sheet.dart';
import 'package:dating_app/presentation/widgets/price_badge.dart';
import 'package:dating_app/core/search/nearby_relevance.dart';
import 'package:dating_app/presentation/widgets/nearby_places_card.dart';
import 'package:dating_app/presentation/widgets/neighborhood_score_card.dart';
import 'package:dating_app/presentation/widgets/property_share_sheet.dart';
import 'package:dating_app/presentation/widgets/tenant_rights_sheet.dart';
import 'package:dating_app/presentation/widgets/term_tooltip.dart';
import 'package:dating_app/presentation/widgets/verification_info_sheet.dart';
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
import 'package:dating_app/presentation/screens/owner_listings_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dating_app/presentation/features/panorama/panorama_psv_tour.dart';
import 'package:dating_app/presentation/features/scan3d/scan3d_viewer.dart';
import 'package:dating_app/presentation/widgets/animations/micro_animations.dart';

// ─── Per-template layout parts ────────────────────────────────────────────────
// Each broker property-listing template lives in its own part file so a designer
// can own and improve one layout in isolation. These are `part` files of THIS
// library, so all `_`-prefixed shared building blocks below remain accessible.
part 'property_templates/classic_template.dart';
part 'property_templates/gallery_editorial_template.dart';
part 'property_templates/cinematic_glass_template.dart';
part 'property_templates/aura_hero_template.dart';
part 'property_templates/market_board_template.dart';
part 'property_templates/estate_card_template.dart';

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

  // ── View-side behavioral signals (fail-soft, no UX impact) ────────────────
  // Captured locally and emitted once on dispose so a single network blip can
  // never affect the screen. All reads are guarded so they can never throw.
  final Stopwatch _viewStopwatch = Stopwatch();
  double _maxScrollDepth = 0.0; // 0..1 fraction of the detail page scrolled
  int _photosViewed = 1; // current image counts as one viewed
  bool _opened360 = false;
  bool _opened3d = false;
  bool _openedVideo = false;
  int _mediaDwellMs = 0;
  bool _contacted = false; // guard so a single contact emits once

  /// Finalizes any background scan for this listing (attaching a finished model)
  /// and refreshes the cached "processing" state. Only the owner has a pending
  /// record; the provider notifies listeners so the banner / viewer updates.
  void _refreshScanState(DatingProvider provider) {
    unawaited(provider.finalizePendingScans());
    unawaited(provider.refreshScanProcessingCache());
  }

  void _onScroll(ScrollMetrics m) {
    if (widget.isLandlordPreview) return;
    final max = m.maxScrollExtent;
    if (max <= 0) return;
    final depth = (m.pixels / max).clamp(0.0, 1.0);
    if (depth > _maxScrollDepth) _maxScrollDepth = depth;
  }

  /// Wraps the (template-shared) tour open so the tap is recorded as media
  /// engagement before delegating to the real handler. Classifies by the
  /// property's available media so 360/3D/video are tracked distinctly.
  void _openTourTracked(RentalProperty p) {
    if (!widget.isLandlordPreview) {
      final tourStart = DateTime.now();
      if (p.hasPanoramaTour) {
        _opened360 = true;
      } else if (p.hasReadyVirtualTour) {
        _opened3d = true;
      } else if (p.videoUrls.isNotEmpty) {
        _openedVideo = true;
      }
      // The tour is a pushed route / sheet; approximate dwell as time until the
      // user is back on this screen by sampling on the next frame after return.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mediaDwellMs += DateTime.now().difference(tourStart).inMilliseconds;
      });
    }
    openPropertyTour(context, p);
  }

  /// Records the in-app contact (like → match/chat) as a funnel + timing
  /// signal, then delegates to the supplied real action.
  void _contactTracked(VoidCallback action) {
    if (!widget.isLandlordPreview && !_contacted) {
      _contacted = true;
      try {
        final svc = AppEvents.instance.service;
        svc.logContactInitiated(
          propertyId: widget.property.id,
          viewToContactMs: _viewStopwatch.elapsedMilliseconds,
        );
        svc.logFunnelStage(
          stage: FunnelStage.contact,
          propertyId: widget.property.id,
        );
      } catch (_) {/* fail-soft */}
    }
    action();
  }

  @override
  void initState() {
    super.initState();
    _viewStopwatch.start();
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
        // Same for a background KIRI 3D scan: re-check it so a finished model
        // gets attached + the "סריקת תלת-מימד" viewer appears on the listing.
        _refreshScanState(provider);
        // View-side funnel signal: the user opened this listing's detail.
        try {
          AppEvents.instance.service.logFunnelStage(
            stage: FunnelStage.view,
            propertyId: widget.property.id,
          );
        } catch (_) {/* fail-soft */}
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Landlord previewing their own listing — refresh the tour state too.
        final provider = context.read<DatingProvider>();
        provider.refreshPropertyTour(widget.property.id);
        _refreshScanState(provider);
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
      // Emit the accumulated view-side signals once, on the way out.
      try {
        final svc = AppEvents.instance.service;
        svc.logDetailScrollDepth(
          propertyId: widget.property.id,
          depth: _maxScrollDepth,
        );
        svc.logMediaEngagement(
          propertyId: widget.property.id,
          photosViewed: _photosViewed,
          opened360: _opened360,
          opened3d: _opened3d,
          openedVideo: _openedVideo,
          mediaDwellMs: _mediaDwellMs,
        );
      } catch (_) {/* fail-soft */}
    }
    _pageController.dispose();
    super.dispose();
  }

  void _handleGalleryPageChanged(String propertyId, int index) {
    setState(() => _currentPage = index);
    if (!widget.isLandlordPreview) {
      // Distinct photos paged through = highest page index reached + 1.
      final reached = index + 1;
      if (reached > _photosViewed) _photosViewed = reached;
      context.read<DatingProvider>().recordPropertyGallerySwipe(
            propertyId,
            index,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Track max scroll depth across whatever scrollable any template renders,
    // without threading a controller through each of them. Read-only, no UX.
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        _onScroll(n.metrics);
        return false; // never consume — preserve scroll behavior exactly
      },
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final p = provider.propertyById(widget.property.id) ?? widget.property;
        final media = p.media;
        final hasVirtualTour =
            p.hasReadyVirtualTour || p.videoUrls.isNotEmpty || p.hasPanoramaTour;
        final title = p.street.isNotEmpty
            ? (p.streetNumber > 0
                ? '${p.propertyType} ב${p.street} ${p.streetNumber}'
                : '${p.propertyType} ב${p.street}')
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
        // A per-property design exists (any viewer), OR the viewer is a broker
        // whose user-level branding chooses a non-classic template.
        final useTemplate = propertyBranding != null || provider.isBroker;

        // "rentlyClassic" is NOT a broker template — it IS the Classic layout
        // rendered below. So we only enter the broker-template path when the
        // RESOLVED template is something other than rentlyClassic. This makes
        // choosing "קלאסי" actually render Classic (previously it silently fell
        // through to Gallery Editorial).
        if (useTemplate &&
            branding.propertyTemplate != BrokerPropertyTemplate.rentlyClassic) {
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
            onLike: () => _contactTracked(() {
              context.read<DatingProvider>().likeProperty(p.id);
              Navigator.of(context).pop();
            }),
            onTour: () => _openTourTracked(p),
            onEdit: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EditPropertyScreen(property: p),
              ),
            ),
          );
        }

        // ── Classic (Rently Classic) layout ──────────────────────────────────
        // Owned by `property_templates/classic_template.dart`.
        return _ClassicTemplate(
          property: p,
          controller: _pageController,
          currentPage: _currentPage,
          onPageChanged: (i) => _handleGalleryPageChanged(p.id, i),
          title: title,
          media: media,
          reviews: reviews,
          avgRating: avgRating,
          hasVirtualTour: hasVirtualTour,
          isLandlordPreview: widget.isLandlordPreview,
          monthlyIncome: provider.tenantProfile?.monthlyIncome,
          onBackTap: () => Navigator.of(context).pop(),
          onShareTap: () => showPropertyShareSheet(context, p),
          onLike: () => _contactTracked(() {
            context.read<DatingProvider>().likeProperty(p.id);
            Navigator.of(context).pop();
          }),
          onTour: () => _openTourTracked(p),
          onEdit: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EditPropertyScreen(property: p),
            ),
          ),
        );
      },
    );
  }
}

// ─── Listing enrichment block (Ask Rently + price/neighborhood badges) ────────
//
// Phase-1 per-listing intelligence, mounted inline by every layout (Classic +
// broker templates). It is built to TOLERATE the backend not having landed yet:
//
//  • Price badge & neighborhood score read enrichment fields defensively. The
//    `RentalProperty` model does not (yet) carry them, so this block fetches
//    them on demand via the generic AWS client and parses each field
//    defensively — any missing/malformed/`insufficient_data` value collapses to
//    nothing. Before the backend exists the fetch simply fails-soft and ONLY
//    the "שאל את Rently" entry remains.
//  • "שאל את Rently" is always available (the entry just opens a chat sheet that
//    itself fails-soft on the network).
//
// The whole block is hidden in landlord-preview mode.
class _ListingEnrichmentBlock extends StatefulWidget {
  const _ListingEnrichmentBlock({
    required this.property,
    this.title = '',
    this.compact = false,
  });

  final RentalProperty property;
  final String title;

  /// Tighter spacing for dense (broker) layouts.
  final bool compact;

  @override
  State<_ListingEnrichmentBlock> createState() =>
      _ListingEnrichmentBlockState();
}

class _ListingEnrichmentBlockState extends State<_ListingEnrichmentBlock> {
  Map<String, dynamic>? _enrichment; // raw {priceBadge, neighborhoodScore, …}

  @override
  void initState() {
    super.initState();
    _loadEnrichment();
  }

  /// Fetches the listing's enrichment payload defensively. Any failure (no
  /// backend yet, network blip, odd shape) leaves [_enrichment] null so the
  /// badges simply don't render — the Ask-Rently entry is unaffected.
  Future<void> _loadEnrichment() async {
    try {
      if (!AwsApiClient.instance.isConfigured) return;
      final res = await AwsApiClient.instance.get(
        '/listing/enrichment',
        query: {'listingId': widget.property.id},
      );
      // Accept either a flat map or a {data:{…}} envelope.
      final data = res['data'];
      final map = data is Map
          ? Map<String, dynamic>.from(data)
          : Map<String, dynamic>.from(res);
      if (!mounted) return;
      // Only keep it if it actually carries an enrichment field we render.
      if (map['priceBadge'] != null || map['neighborhoodScore'] != null) {
        setState(() => _enrichment = map);
      }
    } catch (_) {
      /* fail-soft: badges stay hidden */
    }
  }

  @override
  Widget build(BuildContext context) {
    final gap = widget.compact ? 12.0 : 16.0;
    final children = <Widget>[];

    final priceBadge = PriceBadge(enrichment: _enrichment);
    final neighborhood = NeighborhoodScoreCard(enrichment: _enrichment);

    // PriceBadge / NeighborhoodScoreCard each collapse to SizedBox.shrink when
    // their field is absent, so we add them unconditionally and only insert a
    // gap when something real precedes the next item.
    children.add(priceBadge);
    children.add(neighborhood);
    // Nearby places (schools / kindergartens / clinics / supermarkets / parks),
    // PERSONALISED to the seeker's persona (their profile bio + important details)
    // → only relevant sections show. Self-hides when nothing is relevant.
    final tp = context.read<DatingProvider>().tenantProfile;
    final personaText =
        '${tp?.bio ?? ''} ${(tp?.importantDetails ?? const <String>[]).join(' ')}';
    children.add(NearbyPlacesCard(
      lat: widget.property.lat,
      lon: widget.property.lon,
      city: widget.property.city,
      profile: NearbyProfile.fromText(personaText),
      carousel: true, // detail page → tag carousel, top 5 + "צפה בכולם"
      maxChips: 5,
    ));
    children.add(_AskRentlyEntry(
      property: widget.property,
      title: widget.title,
    ));

    // Interleave gaps without leaving a leading/trailing void from shrunk items.
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) spaced.add(SizedBox(height: gap));
      spaced.add(children[i]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: spaced,
    );
  }
}

/// The "שאל את Rently" entry card — opens the per-listing Q&A chat sheet.
class _AskRentlyEntry extends StatelessWidget {
  const _AskRentlyEntry({required this.property, this.title = ''});

  final RentalProperty property;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: GestureDetector(
        onTap: () => showAskRentlySheet(
          context,
          property: property,
          listingTitle: title,
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.10),
                AppColors.primary.withValues(alpha: 0.04),
              ],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: AppColors.primary.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(IconsaxPlusBold.message_question,
                    color: Colors.white, size: 25),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'שאל את Rently',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'שאלו כל דבר על הדירה — חיות, קומה, תחבורה ועוד',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(IconsaxPlusLinear.arrow_left_2,
                  size: 18, color: AppColors.primary),
            ],
          ),
        ),
      ),
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
              // Save + Share buttons (grouped, top-start in RTL).
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Save / bookmark toggle → the listing shows in "הדירות ששמרתי".
                  Consumer<DatingProvider>(
                    builder: (context, provider, _) {
                      final saved = provider.isSaved(property.id);
                      return ScaleBounce(
                        onTap: () => provider.toggleSave(property.id),
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
                          child: RentlyIcon(
                            saved
                                ? IconsaxPlusBold.save_2
                                : IconsaxPlusLinear.save_2,
                            color: saved
                                ? AppColors.primary
                                : const Color(0xFF0F172A),
                            size: 20,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
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
    // Each branch lifts its layout into a dedicated, designer-owned widget that
    // lives in `property_templates/<name>.dart`. The widgets are constructed
    // with exactly the data + callbacks their layout needs.
    final content = switch (branding.propertyTemplate) {
      BrokerPropertyTemplate.acidHero => _AuraHeroTemplate(
          property: property,
          branding: branding,
          controller: controller,
          currentPage: currentPage,
          onPageChanged: onPageChanged,
          reviews: reviews,
          avgRating: avgRating,
          hasVirtualTour: hasVirtualTour,
          isLandlordPreview: isLandlordPreview,
          onBackTap: onBackTap,
          onShareTap: onShareTap,
          onTour: onTour,
        ),
      BrokerPropertyTemplate.dashboardGlass => _MarketBoardTemplate(
          property: property,
          branding: branding,
          controller: controller,
          currentPage: currentPage,
          onPageChanged: onPageChanged,
          reviews: reviews,
          hasVirtualTour: hasVirtualTour,
          isLandlordPreview: isLandlordPreview,
          onBackTap: onBackTap,
          onShareTap: onShareTap,
          onLike: onLike,
          onTour: onTour,
        ),
      BrokerPropertyTemplate.estateCard => _EstateCardTemplate(
          property: property,
          branding: branding,
          controller: controller,
          currentPage: currentPage,
          onPageChanged: onPageChanged,
          reviews: reviews,
          hasVirtualTour: hasVirtualTour,
          isLandlordPreview: isLandlordPreview,
          onBackTap: onBackTap,
          onShareTap: onShareTap,
          onTour: onTour,
        ),
      BrokerPropertyTemplate.galleryEditorial => _GalleryEditorialTemplate(
          property: property,
          branding: branding,
          controller: controller,
          currentPage: currentPage,
          onPageChanged: onPageChanged,
          reviews: reviews,
          hasVirtualTour: hasVirtualTour,
          isLandlordPreview: isLandlordPreview,
          onBackTap: onBackTap,
          onShareTap: onShareTap,
          onTour: onTour,
        ),
      BrokerPropertyTemplate.cinematicGlass => _CinematicGlassTemplate(
          property: property,
          branding: branding,
          controller: controller,
          currentPage: currentPage,
          onPageChanged: onPageChanged,
          reviews: reviews,
          hasVirtualTour: hasVirtualTour,
          isLandlordPreview: isLandlordPreview,
          onBackTap: onBackTap,
          onShareTap: onShareTap,
          onTour: onTour,
        ),
      // Unreachable: rentlyClassic is handled by the Classic layout in
      // PropertyDetailScreen.build and never reaches this broker-template
      // widget. Kept only to satisfy switch exhaustiveness.
      BrokerPropertyTemplate.rentlyClassic => _GalleryEditorialTemplate(
          property: property,
          branding: branding,
          controller: controller,
          currentPage: currentPage,
          onPageChanged: onPageChanged,
          reviews: reviews,
          hasVirtualTour: hasVirtualTour,
          isLandlordPreview: isLandlordPreview,
          onBackTap: onBackTap,
          onShareTap: onShareTap,
          onTour: onTour,
        ),
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

}

/// Renders the COMPLETE set of Rently-Classic content sections (specs grid,
/// signal strip, gallery thumbnails, source URL, "why this match", owner,
/// features, reviews, virtual-tour/360/3D entry, map) so every non-classic
/// template reaches full parity. Centralizing this here makes it structurally
/// impossible for a single template to drop a section.
class _ParitySections extends StatelessWidget {
  const _ParitySections({
    required this.property,
    required this.branding,
    required this.controller,
    required this.reviews,
    required this.hasVirtualTour,
    required this.isLandlordPreview,
    required this.onShareTap,
    required this.onTour,
    this.dark = false,
  });

  final RentalProperty property;
  final BrokerBrandingConfig branding;
  final PageController controller;
  final List<AppReview> reviews;
  final bool hasVirtualTour;
  final bool isLandlordPreview;
  final VoidCallback onShareTap;
  final VoidCallback onTour;
  final bool dark;

  Color get _onSurface => dark ? Colors.white : branding.secondaryColor;
  Color get _muted => dark
      ? Colors.white.withValues(alpha: 0.66)
      : branding.secondaryColor.withValues(alpha: 0.62);
  Color get _cardSurface =>
      dark ? Colors.white.withValues(alpha: 0.06) : Colors.white;

  Widget _header(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, color: branding.primaryColor, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: _onSurface,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = property.media;
    final children = <Widget>[];

    // ── Highlights / market signals ───────────────────────────────────────
    if (_PropertySignalStrip.shouldShow(context, property)) {
      children.add(_PropertySignalStrip(property: property));
      children.add(const SizedBox(height: 24));
    }

    // ── Gallery thumbnails ────────────────────────────────────────────────
    if (media.isNotEmpty) {
      children.add(_header('גלריה', IconsaxPlusLinear.gallery));
      children.add(
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: media.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, index) => GestureDetector(
              onTap: () {
                if (controller.hasClients) {
                  controller.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOut,
                  );
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 110,
                  height: 92,
                  child: SafeMedia(
                    media: media[index],
                    fit: BoxFit.cover,
                    fallback: _ImageFallback(city: property.city),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      children.add(const SizedBox(height: 26));
    }

    // ── Property facts (rooms / size / floor / condition / parking / lift) ──
    children.add(_header('פרטי הנכס', IconsaxPlusLinear.building_3));
    children.add(_PropertyFactsCard(property));
    children.add(const SizedBox(height: 26));

    // ── Phase-1 listing intelligence: price/neighborhood badges (only when the
    // backend enrichment is present) + the "שאל את Rently" Q&A entry. Each part
    // self-hides when its data is absent; omitted entirely in landlord preview.
    if (!isLandlordPreview) {
      children.add(_ListingEnrichmentBlock(property: property, compact: true));
      children.add(const SizedBox(height: 26));
    }

    // ── Source / origin URL ───────────────────────────────────────────────
    if (property.url.isNotEmpty) {
      children.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: _header('אתר מקור', IconsaxPlusLinear.global)),
            GestureDetector(
              onTap: () async {
                await launchUrl(Uri.parse(property.url),
                    mode: LaunchMode.externalApplication);
              },
              child: Text(
                'צפה במקור',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: branding.primaryColor,
                ),
              ),
            ),
          ],
        ),
      );
      children.add(
        Text(
          'נכס זה פורסם במקור באתר ${Uri.parse(property.url).host}. באפשרותך לפתוח את המודעה המקורית לצפייה בפרטים המלאים.',
          style: TextStyle(
            color: _muted,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
      );
      children.add(const SizedBox(height: 26));
    }

    // ── Why this match (scorecard) ────────────────────────────────────────
    if (!isLandlordPreview) {
      children.add(_header('למה ההתאמה הזו', IconsaxPlusLinear.flash_1));
      children.add(_MatchInsightCard(property: property));
      children.add(const SizedBox(height: 26));
    }

    // ── Owner / contact (with verified badge inside the card) ─────────────
    children.add(_header('בעל הנכס', IconsaxPlusLinear.profile_2user));
    children.add(_OwnerCard(property: property));
    children.add(const SizedBox(height: 26));

    // ── Virtual tours / media (360° + 3D scan) ────────────────────────────
    final has360 = property.hasPanoramaTour;
    final has3d = _scan3dGlbUrl(property) != null ||
        _scan3dSplatUrl(property) != null;
    children.add(_header(
      has360 || has3d ? 'סיורים' : 'סיור וירטואלי',
      IconsaxPlusLinear.video_play,
    ));

    final mediaCards = <Widget>[];
    if (has360) {
      mediaCards.add(_MediaTourCard(
        icon: Icons.threesixty_rounded,
        title: 'סיור 360°',
        subtitle: 'סיור פנורמי אינטראקטיבי — הסתובבו בדירה',
        branding: branding,
        surface: _cardSurface,
        onSurface: _onSurface,
        muted: _muted,
        onTap: () => PanoramaPsvTourView.open(context, property.panoramaTour!),
      ));
    }
    if (has3d) {
      mediaCards.add(_MediaTourCard(
        icon: Icons.view_in_ar_rounded,
        title: 'סריקת תלת-מימד (מתקדם)',
        subtitle: '✓ הסריקה מוכנה — סובבו והתקרבו מכל זווית',
        branding: branding,
        surface: _cardSurface,
        onSurface: _onSurface,
        muted: _muted,
        onTap: () {
          // Multi-room scan → room-switcher; single scan → the classic viewer.
          final rooms = property.model3d?.viewableRooms ?? const [];
          if (rooms.length > 1) {
            Scan3dViewerScreen.openRooms(context, rooms,
                title: 'סריקת תלת-מימד');
          } else {
            Scan3dViewerScreen.open(
              context,
              meshGlbUrl: _scan3dGlbUrl(property),
              splatUrl: _scan3dSplatUrl(property),
              title: 'סריקת תלת-מימד',
            );
          }
        },
      ));
    }

    // A 3D scan is reconstructing in the background — set expectations that it
    // takes a few minutes and the owner can leave; it appears here when ready.
    final scanProcessing =
        context.watch<DatingProvider>().isScanProcessing(property.id);
    if (scanProcessing && !has3d) {
      mediaCards.add(_Scan3dProcessingCard(
        surface: _cardSurface,
        onSurface: _onSurface,
        muted: _muted,
      ));
    }

    // The scan is already viewable (via .ply) but the fast .ksplat is still being
    // converted server-side — show a live timer so the owner sees it's happening.
    // Disappears once the .ksplat is ready (fresh fetch) or the 3-min window ends.
    final optimizingSince =
        context.watch<DatingProvider>().scanOptimizingSince(property.id);
    final ksplatReady = property.model3d?.ksplatUrl.trim().isNotEmpty ?? false;
    if (optimizingSince != null && !ksplatReady) {
      mediaCards.add(_Scan3dProcessingCard(
        surface: _cardSurface,
        onSurface: _onSurface,
        muted: _muted,
        since: optimizingSince,
        optimizing: true,
      ));
    }

    if (mediaCards.isEmpty) {
      // No 360 and no 3D scan: keep the existing single entry (video /
      // processing / "request a scan" states) so the CTA is never dead.
      children.add(_TourEntryCard(
        property: property,
        branding: branding,
        hasVirtualTour: hasVirtualTour,
        surface: _cardSurface,
        onSurface: _onSurface,
        muted: _muted,
        onTour: onTour,
      ));
    } else {
      for (var i = 0; i < mediaCards.length; i++) {
        if (i > 0) children.add(const SizedBox(height: 12));
        children.add(mediaCards[i]);
      }
    }
    children.add(const SizedBox(height: 26));

    // ── Key features / amenities ──────────────────────────────────────────
    if (property.features.isNotEmpty) {
      children.add(_header('מאפיינים חשובים', IconsaxPlusLinear.flash_1));
      children.add(_FeatureWrap(features: property.features));
      children.add(const SizedBox(height: 26));
    }

    // ── Reviews ───────────────────────────────────────────────────────────
    if (reviews.isNotEmpty) {
      children.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: _header('חוות דעת', IconsaxPlusLinear.star_1)),
            Text(
              '${reviews.length} ביקורות',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _muted,
              ),
            ),
          ],
        ),
      );
      children.add(_HorizontalReviewsList(reviews));
      children.add(const SizedBox(height: 26));
    }

    // ── Map / location ────────────────────────────────────────────────────
    children.add(_header('מיקום', IconsaxPlusLinear.location));
    children.add(_MapSection(property: property));

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// Branded entry card for the virtual tour / 360° walkthrough / 3D scan.
class _TourEntryCard extends StatelessWidget {
  const _TourEntryCard({
    required this.property,
    required this.branding,
    required this.hasVirtualTour,
    required this.surface,
    required this.onSurface,
    required this.muted,
    required this.onTour,
  });

  final RentalProperty property;
  final BrokerBrandingConfig branding;
  final bool hasVirtualTour;
  final Color surface;
  final Color onSurface;
  final Color muted;
  final VoidCallback onTour;

  @override
  Widget build(BuildContext context) {
    final isProcessing = property.virtualTour?.isProcessing == true;
    final has360 = property.hasPanoramaTour;
    final hasVideo = property.videoUrls.isNotEmpty;
    final subtitle = has360
        ? 'סיור 360° אינטראקטיבי — הסתובבו בדירה'
        : hasVirtualTour
            ? 'סריקת תלת־ממד / וידאו זמינה לצפייה'
            : isProcessing
                ? 'הסריקה בהכנה — תהיה זמינה בקרוב'
                : 'בקשו סריקת תלת־ממד מבעל הנכס';

    return GestureDetector(
      onTap: onTour,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: branding.primaryColor.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: branding.primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                has360 ? Icons.threesixty_rounded : Icons.view_in_ar_rounded,
                color: branding.primaryColor,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    has360
                        ? 'סיור 360°'
                        : hasVideo && !hasVirtualTour
                            ? 'וידאו הנכס'
                            : 'סיור תלת־ממדי',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Icon(IconsaxPlusLinear.arrow_left,
                size: 16, color: branding.primaryColor),
          ],
        ),
      ),
    );
  }
}

/// Returns a textured-mesh GLB url for [property]'s 3D scan, or null when none.
String? _scan3dGlbUrl(RentalProperty property) {
  final m = property.model3d;
  if (m == null) return null;
  final glb = m.glbUrl.trim();
  return glb.isEmpty ? null : glb;
}

/// Returns a Gaussian-splat url for [property]'s 3D scan, or null. Prefers the
/// compact, fast-loading `.ksplat` (produced async by rentch-splat-convert) and
/// falls back to the raw `.ply` while conversion is still catching up.
String? _scan3dSplatUrl(RentalProperty property) {
  final m = property.model3d;
  if (m == null) return null;
  final ksplat = m.ksplatUrl.trim();
  if (ksplat.isNotEmpty) return ksplat;
  final ply = m.plyUrl.trim();
  return ply.isEmpty ? null : ply;
}

/// Branded, tappable card for a single virtual-media entry (360° tour or 3D
/// scan). Mirrors [_TourEntryCard]'s look so the section reads consistently.
class _MediaTourCard extends StatelessWidget {
  const _MediaTourCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.branding,
    required this.surface,
    required this.onSurface,
    required this.muted,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final BrokerBrandingConfig branding;
  final Color surface;
  final Color onSurface;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: branding.primaryColor.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: branding.primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: branding.primaryColor, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Icon(IconsaxPlusLinear.arrow_left,
                size: 16, color: branding.primaryColor),
          ],
        ),
      ),
    );
  }
}

/// "מעבד… נודיע כשמוכן" notice for a 3D scan still reconstructing in the
/// background. Sets expectations (a few minutes, can leave) and reassures the
/// owner the scan wasn't lost — it surfaces here as a viewer once ready.
class _Scan3dProcessingCard extends StatefulWidget {
  const _Scan3dProcessingCard({
    required this.surface,
    required this.onSurface,
    required this.muted,
    this.since,
    this.optimizing = false,
  });

  final Color surface;
  final Color onSurface;
  final Color muted;

  /// When the current processing started — drives the live count-up timer. Null
  /// falls back to a spinner-only card (the older cloud-reconstruction path).
  final DateTime? since;

  /// True = a fast-splat optimize of an already-viewable scan (different copy);
  /// false = a full 3D reconstruction that isn't viewable yet.
  final bool optimizing;

  @override
  State<_Scan3dProcessingCard> createState() => _Scan3dProcessingCardState();
}

class _Scan3dProcessingCardState extends State<_Scan3dProcessingCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (widget.since != null) {
      // Tick once a second so the mm:ss timer stays live.
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _elapsed() {
    final s = DateTime.now().difference(widget.since!).inSeconds.clamp(0, 5999);
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.optimizing
        ? 'מייעל את הסריקה לטעינה מהירה…'
        : 'מעבד סריקת תלת-מימד…';
    final subtitle = widget.optimizing
        ? 'הסריקה כבר ניתנת לצפייה; מכינים גרסה חדה וקלה שנטענת מהר.'
        : 'בונים את המודל — כמה דקות. אפשר לעזוב, נודיע כשמוכן.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: widget.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: widget.muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (widget.since != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _elapsed(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ],
      ),
    );
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
  const _FloatingNavBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

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
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

Future<void> openPropertyTour(
  BuildContext context,
  RentalProperty property,
) async {
  // Prefer the DIY 360° panorama walkthrough when the owner captured one — it's
  // a real "look around / walk to the next point" experience, even without a
  // heavy 3D scan.
  if (property.hasPanoramaTour) {
    await PanoramaPsvTourView.open(context, property.panoramaTour!);
    return;
  }
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
              const SizedBox(height: 12),
              // Tap the owner → their full listings page (also shareable).
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OwnerListingsScreen(
                      ownerUserId: property.ownerUserId,
                      ownerName: property.ownerName,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        RentlyIcon(IconsaxPlusLinear.house_2,
                            size: 16, color: Color(0xFF13BEC9)),
                        SizedBox(width: 6),
                        Text(
                          'צפה בכל הדירות של בעל הנכס',
                          style: TextStyle(
                            color: Color(0xFF13BEC9),
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                    const RentlyIcon(IconsaxPlusLinear.arrow_left,
                        size: 14, color: Color(0xFF13BEC9)),
                  ],
                ),
              ),
              // Tenants (no mutual like) can ask to message the owner. The
              // request lands in the owner's "מבקשים לשלוח הודעה" inbox.
              if (!provider.isLandlord) ...[
                const SizedBox(height: 14),
                _MessageRequestButton(property: property),
              ],
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

/// "בקש לשלוח הודעה" — lets a tenant with no mutual like reach out to the owner.
/// The request lands in the owner's dedicated messages section.
class _MessageRequestButton extends StatelessWidget {
  const _MessageRequestButton({required this.property});
  final RentalProperty property;

  Future<void> _open(BuildContext context, DatingProvider provider) async {
    final controller = TextEditingController();
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'בקשה לשלוח הודעה לבעל הנכס',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                maxLines: 3,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: 'כתוב הודעה קצרה… (למשל: מתי אפשר לראות?)',
                  hintTextDirection: TextDirection.rtl,
                  filled: true,
                  fillColor: const Color(0xFFF1F5F8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('שלח בקשה',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (sent == true) {
      await provider.requestToMessage(property, note: controller.text);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(milliseconds: 2600),
          content: Text('הבקשה נשלחה — היא תופיע אצל בעל הנכס תחת "מבקשים לשלוח הודעה"'),
        ));
      }
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DatingProvider>();
    final already = provider.hasThreadForProperty(property.id);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: already ? null : () => _open(context, provider),
        icon: const RentlyIcon(IconsaxPlusLinear.message_text, size: 18),
        label: Text(already ? 'הבקשה נשלחה' : 'בקש לשלוח הודעה'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
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

// ─── Content widgets ──────────────────────────────────────────────────────────

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
        // Tap-to-explain for known rental terms (ממ"ד, בטוחות…); no-op otherwise.
        return TermTooltip(
          term: f,
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

/// Tenant affordability snapshot for a rental: rent-to-income band (when income
/// is known) + the up-front move-in total breakdown, plus a "מה הזכויות שלי?"
/// entry point. Pure read-only; never blocks. When income is null it shows a
/// gentle prompt to add it (deep-links nowhere — the profile editor owns that).
class _AffordabilityStrip extends StatelessWidget {
  const _AffordabilityStrip({
    required this.property,
    required this.monthlyIncome,
  });

  final RentalProperty property;
  final int? monthlyIncome;

  static const _bandColors = <RentBand, Color>{
    RentBand.comfortable: Color(0xFF22C55E),
    RentBand.stretched: Color(0xFFF59E0B),
    RentBand.high: Color(0xFFFF5A67),
    RentBand.unknown: Color(0xFF64748B),
  };

  static const _bandLabels = <RentBand, String>{
    RentBand.comfortable: 'נוח לתקציב',
    RentBand.stretched: 'מתיחה תקציבית',
    RentBand.high: 'נטל גבוה',
    RentBand.unknown: 'הוסיפו הכנסה לבדיקת התאמה',
  };

  @override
  Widget build(BuildContext context) {
    final result = Affordability.assess(
      monthlyRent: property.price,
      monthlyIncome: monthlyIncome,
    );
    final color = _bandColors[result.band]!;
    final ratioPct = result.rentToIncomePercent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RentlyIcon(IconsaxPlusLinear.wallet_money, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.band == RentBand.unknown
                      ? 'הזן הכנסה לבדיקת התאמה'
                      : '${_bandLabels[result.band]}'
                          '${ratioPct != null ? ' · $ratioPct% מההכנסה' : ''}',
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Move-in cost breakdown — what's needed in cash on day one.
          for (final item in result.lineItems)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '₪${item.amount}',
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 16, color: Color(0xFFE2E8F0)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'סה״כ עלות כניסה',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '₪${result.moveInTotal}',
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => TenantRightsSheet.show(
                context,
                monthlyRent: property.price,
                termMonths: 12,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.navy,
                side: const BorderSide(color: Color(0xFFE2E8F0)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: RentlyIcon(IconsaxPlusLinear.shield_tick,
                  size: 16, color: AppColors.primary),
              label: const Text(
                'מה הזכויות שלי?',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
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
          GestureDetector(
            onTap: () => VerificationInfoSheet.show(context),
            child: const _PropertySignalChip(
              icon: IconsaxPlusLinear.verify,
              label: 'דירה מאומתת',
              color: Color(0xFF13BEC9),
              showInfoHint: true,
            ),
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
    this.showInfoHint = false,
  });

  final IconData icon;
  final String label;
  final Color color;

  /// Adds a trailing "?" hint so the verified chip reads as tappable.
  final bool showInfoHint;

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
          if (showInfoHint) ...[
            const SizedBox(width: 5),
            Icon(Icons.help_outline_rounded, size: 14, color: color),
          ],
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

/// Collapsible "למה ההתאמה הזו?" expander. Collapsed by default; a row with a
/// "?" icon on the trailing side that, when tapped, reveals the existing
/// [_MatchInsightCard] scorecard as its body.
class _MatchInsightDropdown extends StatefulWidget {
  const _MatchInsightDropdown({required this.property});
  final RentalProperty property;

  @override
  State<_MatchInsightDropdown> createState() => _MatchInsightDropdownState();
}

class _MatchInsightDropdownState extends State<_MatchInsightDropdown> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              const Icon(IconsaxPlusLinear.flash_1,
                  color: Color(0xFF13BEC9), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'למה ההתאמה הזו?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    IconsaxPlusLinear.arrow_down_1,
                    size: 16,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF13BEC9).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text(
                    '?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF13BEC9),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: _MatchInsightCard(property: widget.property),
          ),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 220),
        ),
        const SizedBox(height: 18),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
      ],
    );
  }
}

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
