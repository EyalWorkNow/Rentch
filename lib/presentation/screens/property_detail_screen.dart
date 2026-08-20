import 'dart:async';
import 'dart:math' show max;
import 'package:dating_app/core/ui/platform_fx.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/services.dart';
import 'package:dating_app/core/config/media_cdn.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/utils/helpers/property_label_helper.dart';
import 'package:dating_app/core/finance/affordability.dart';
import 'package:dating_app/core/matching/match_models.dart';
import 'package:dating_app/data/models/broker_design_models.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/presentation/features/billing/boost_flow.dart';
import 'package:dating_app/core/services/behavior_insights_service.dart';
import 'package:dating_app/core/services/event_service.dart';
import 'package:dating_app/core/services/interaction_service.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/main.dart' show markInAppBack;
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/widgets/ask_rently_sheet.dart';
import 'package:dating_app/presentation/widgets/price_badge.dart';
import 'package:dating_app/core/search/nearby_relevance.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart'
    show IsraelGeoIndex, NearbyPlace;
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
import 'package:dating_app/presentation/screens/add_property_screen.dart'
    show EditPropertyScreen;
import 'package:dating_app/presentation/screens/owner_listings_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dating_app/data/models/panorama_tour.dart';
import 'package:dating_app/presentation/features/panorama/panorama_capture_screen.dart';
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
    this.entrySource = 'detail',
    this.entryRank,
  });
  final RentalProperty property;
  final bool isLandlordPreview;

  /// Where the user came from when they opened this listing
  /// ('search'|'deck'|'cf'|'saved'|'detail'). Threaded into the interaction
  /// record so the store learns WHY the user entered. Defaults to 'detail'
  /// (a link/notification/deep open) so every existing call site stays valid.
  final String entrySource;

  /// The position/rank at which this property was surfaced in the source list
  /// (0-based). Null when the source has no meaningful ordering.
  final int? entryRank;

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

  // Lead-conversion funnel: timestamp of the previous step for THIS detail view,
  // so each step carries its latency-from-prev. Fail-soft, no UX impact.
  DateTime? _lastFunnelStepAt;

  /// Emits one lead-funnel step (raw `leadFunnelStep` event + BehaviorInsights
  /// mirror), computing msSincePrevStep from the previous step reached on this
  /// screen. Fully fail-soft; a no-op in landlord-preview mode.
  void _noteFunnelStep(LeadFunnelStep step) {
    if (widget.isLandlordPreview) return;
    try {
      final now = DateTime.now();
      final delta = _lastFunnelStepAt == null
          ? null
          : now.difference(_lastFunnelStepAt!).inMilliseconds;
      _lastFunnelStepAt = now;
      AppEvents.instance.service.logLeadFunnelStep(
        step: step,
        propertyId: widget.property.id,
        msSincePrevStep: delta,
      );
      BehaviorInsights.instance.noteFunnelStep(step);
    } catch (_) {/* fail-soft */}
  }

  /// Finalizes any background scan for this listing (attaching a finished model)
  /// and refreshes the cached "processing" state. Only the owner has a pending
  /// record; the provider notifies listeners so the banner / viewer updates.
  void _refreshScanState(DatingProvider provider) {
    unawaited(provider.finalizePendingScans());
    unawaited(provider.refreshScanProcessingCache());
  }

  /// Warms the image cache for the photos adjacent to [index] so swiping to
  /// them is instant instead of a cold network fetch + decode behind the
  /// 300ms fade-in — nothing precached the gallery's neighbors before, so
  /// every swipe to a not-yet-seen photo showed a blank frame for a beat.
  /// Uses the exact same provider [SafeImage] itself resolves through (see
  /// [SafeImage.precache]) so this actually warms the slot the real widget
  /// hits, not a differently-keyed one.
  void _precacheGalleryNeighbors(int index) {
    final media = widget.property.media;
    if (media.isEmpty) return;
    final width = (MediaQuery.of(context).size.width *
            MediaQuery.of(context).devicePixelRatio)
        .round()
        .clamp(64, 2048);
    for (final i in [index - 1, index + 1]) {
      if (i < 0 || i >= media.length) continue;
      final m = media[i];
      if (!m.isImage) continue;
      SafeImage.precache(context, m.url, width);
    }
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
    // Landlord viewing their own listing with no tour yet → this button UPLOADS
    // a 360 tour (captures + saves), rather than the tenant-facing "request".
    if (widget.isLandlordPreview &&
        !p.hasPanoramaTour &&
        !p.hasReadyVirtualTour) {
      _captureAndSaveTour(p);
      return;
    }
    if (!widget.isLandlordPreview) {
      final tourStart = DateTime.now();
      if (p.hasPanoramaTour) {
        _opened360 = true;
      } else if (p.hasReadyVirtualTour) {
        _opened3d = true;
      } else if (p.videoUrls.isNotEmpty) {
        _openedVideo = true;
      }
      // Lead funnel: engaging rich media (360 / 3D / video) on the way to contact.
      _noteFunnelStep(LeadFunnelStep.media);
      // The tour is a pushed route / sheet; approximate dwell as time until the
      // user is back on this screen by sampling on the next frame after return.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mediaDwellMs += DateTime.now().difference(tourStart).inMilliseconds;
      });
    }
    openPropertyTour(context, p);
  }

  // Landlord uploads a 360 tour for their listing: reuse the same capture flow
  // the add-property form uses, then persist the result onto the property.
  Future<void> _captureAndSaveTour(RentalProperty p) async {
    final tour = await Navigator.of(context).push<PropertyPanoramaTour>(
      MaterialPageRoute(
        builder: (_) => PanoramaCaptureScreen(initial: p.panoramaTour),
      ),
    );
    if (tour == null || tour.isEmpty || !mounted) return;
    await context
        .read<DatingProvider>()
        .updateLandlordProperty(p.copyWith(panoramaTour: tour));
    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.propertyDetailScreen1648cbc8),
        duration: const Duration(milliseconds: 2200),
      ));
    }
  }

  /// Records the in-app contact (like → match/chat) as a funnel + timing
  /// signal, then delegates to the supplied real action.
  void _contactTracked(VoidCallback action) {
    if (widget.isLandlordPreview || _contacted) {
      action();
      return;
    }
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
      // Lead funnel: the contact / "leave details" button was TAPPED (intent).
      _noteFunnelStep(LeadFunnelStep.contactIntent);
      // Strongest funnel outcome for the search that surfaced this listing.
      _analyticsProvider?.recordContactOutcome(
        widget.property.id,
        viewToContactMs: _viewStopwatch.elapsedMilliseconds,
        entrySource: widget.entrySource,
        entryRank: widget.entryRank,
      );
    } catch (_) {/* fail-soft */}
    action();
    // [action] performs the like → the lead is actually submitted to the owner.
    _noteFunnelStep(LeadFunnelStep.contactSubmitted);
  }

  @override
  void initState() {
    super.initState();
    _viewStopwatch.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _precacheGalleryNeighbors(_currentPage);
    });
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
        // Lead-conversion funnel: opened the full detail page.
        _noteFunnelStep(LeadFunnelStep.detail);
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
        // Upsert the rich per-property engagement to the interaction store: the
        // core "how long on each apartment + what interested them" capture,
        // reusing the exact signals already computed above. A very short visit
        // is a 'bounce'; anything longer is a real 'view'.
        final dwellMs = _viewStopwatch.elapsedMilliseconds;
        unawaited(InteractionService.instance.record(
          propertyId: widget.property.id,
          dwellMs: dwellMs,
          photosViewed: _photosViewed,
          opened360: _opened360,
          opened3d: _opened3d,
          openedVideo: _openedVideo,
          scrollDepth: _maxScrollDepth,
          entrySource: widget.entrySource,
          entryRank: widget.entryRank,
          action: dwellMs < 3000 ? 'bounce' : 'view',
        ));
      } catch (_) {/* fail-soft */}
    }
    _pageController.dispose();
    super.dispose();
  }

  void _handleGalleryPageChanged(String propertyId, int index) {
    // Plain assignment, not setState: the gallery widgets track the
    // PageController directly now (see _ImageGallery/_TemplateHeroMedia), so
    // this no longer needs to rebuild the whole detail screen on every swipe
    // — that full-page rebuild (specs, match insight, map, reviews…) was
    // exactly what made the photo transition hitch. `_currentPage` still
    // matters as the initial page value if this screen rebuilds for an
    // unrelated reason.
    _currentPage = index;
    _precacheGalleryNeighbors(index);
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
    // Narrowed from a plain Consumer<DatingProvider>, which re-ran this
    // whole (heavy) detail-page builder on EVERY DatingProvider
    // notifyListeners() anywhere in the app — including the postFrame
    // recordPropertyView/refreshPropertyTour/scan-state polls below, whose
    // resolution used to cause visible flicker/jank shortly after the page
    // opens even when they touched a different property (or nothing this
    // page reads at all). Selector recomputes [_DetailWatch] on every
    // notification but only actually rebuilds the subtree when one of its
    // fields differs — every provider-derived value this builder reads is
    // included so no legitimate update goes missing.
    return Selector<DatingProvider, _DetailWatch>(
      selector: (context, provider) => _DetailWatch(
        isLandlordPreviewGone: widget.isLandlordPreview &&
            !provider.myProperties.any((m) => m.id == widget.property.id),
        property: provider.propertyById(widget.property.id) ?? widget.property,
        reviews: provider.propertyReviews(widget.property.id),
        brokerBranding: provider.brokerBranding,
        isBroker: provider.isBroker,
        monthlyIncome: provider.tenantProfile?.monthlyIncome,
      ),
      builder: (context, watch, _) {
        final l10n = AppLocalizations.of(context)!;
        // Landlord viewing their OWN listing's preview: if the app already
        // knows it's gone, myProperties is authoritative (unlike the general
        // catalog, which can miss it just from pagination/caching, not
        // necessarily deletion) — don't silently freeze on the construction-
        // time snapshot forever with fully "live" Edit/Boost/Share buttons for
        // a listing that no longer exists (this screen has no lifecycle/
        // route-resume hook to notice a deletion that happened elsewhere).
        if (watch.isLandlordPreviewGone) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.property.address)),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.home_outlined,
                        size: 56, color: AppColors.textDisabled),
                    const SizedBox(height: 16),
                    Text(
                      l10n.propertyDetailScreenListingRemoved,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 16, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final p = watch.property;
        final media = p.media;
        final hasVirtualTour = p.hasReadyVirtualTour ||
            p.videoUrls.isNotEmpty ||
            p.hasPanoramaTour;
        final title = p.street.isNotEmpty
            ? (p.streetNumber > 0
                ? l10n.propertyDetailScreenCfa0c95c(
                    p.propertyType, p.street, p.streetNumber)
                : l10n.propertyDetailScreenC9a1c5dd(p.propertyType, p.street))
            : l10n.propertyDetailScreen0196a48c(p.propertyType, p.city);
        final reviews = watch.reviews;
        final avgRating = context.read<DatingProvider>().reviewAverage(reviews);
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
        final branding = propertyBranding ?? watch.brokerBranding;
        // A per-property design exists (any viewer), OR the viewer is a broker
        // whose user-level branding chooses a non-classic template.
        final useTemplate = propertyBranding != null || watch.isBroker;

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
            onBackTap: () {
              markInAppBack();
              Navigator.of(context).pop();
            },
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
          monthlyIncome: watch.monthlyIncome,
          onBackTap: () {
            markInAppBack();
            Navigator.of(context).pop();
          },
          onShareTap: () => showPropertyShareSheet(context, p),
          onBoost: () => showBoostFlow(context, p),
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

/// Value watched by [_PropertyDetailScreenState._buildContent]'s Selector —
/// every DatingProvider-derived field the builder actually reads. Selector
/// recomputes this on every provider notifyListeners() but only rebuilds the
/// subtree when it compares unequal to the previous value, so unrelated
/// provider notifications (a different listing's polling, other screens'
/// actions) no longer force a full rebuild of this (heavy) detail page.
/// Uses `==`/hashCode (not a record) so it stays a valid Selector value type
/// with an explicit, reviewable equality — [RentalProperty] and
/// [BrokerBrandingConfig] have no value equality of their own, so field
/// comparisons here are by reference identity, which DatingProvider's
/// caching (rebuilds a fresh instance only for what actually changed) makes
/// meaningful — see propertyById/_setPropertySignals.
class _DetailWatch {
  const _DetailWatch({
    required this.isLandlordPreviewGone,
    required this.property,
    required this.reviews,
    required this.brokerBranding,
    required this.isBroker,
    required this.monthlyIncome,
  });

  final bool isLandlordPreviewGone;
  final RentalProperty property;
  final List<AppReview> reviews;
  final BrokerBrandingConfig brokerBranding;
  final bool isBroker;
  final int? monthlyIncome;

  @override
  bool operator ==(Object other) =>
      other is _DetailWatch &&
      other.isLandlordPreviewGone == isLandlordPreviewGone &&
      identical(other.property, property) &&
      identical(other.reviews, reviews) &&
      identical(other.brokerBranding, brokerBranding) &&
      other.isBroker == isBroker &&
      other.monthlyIncome == monthlyIncome;

  @override
  int get hashCode => Object.hash(
        isLandlordPreviewGone,
        identityHashCode(property),
        identityHashCode(reviews),
        identityHashCode(brokerBranding),
        isBroker,
        monthlyIncome,
      );
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
    // Defer the enrichment HTTP call until after the first paint so it
    // doesn't compete with the very first build/layout pass of this screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadEnrichment();
    });
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
    final provider = context.read<DatingProvider>();
    final tp = provider.tenantProfile;
    final personaText =
        '${tp?.bio ?? ''} ${(tp?.importantDetails ?? const <String>[]).join(' ')}';
    children.add(_NearbySection(
      property: widget.property,
      listView: NearbyPlacesCard(
        lat: widget.property.lat,
        lon: widget.property.lon,
        city: widget.property.city,
        profile: NearbyProfile.fromText(personaText),
        carousel: true, // detail page → tag carousel, top 5 + "צפה בכולם"
        maxChips: 5,
        showAllKinds: true, // expose EVERY nearby layer with data (persona-first)
        preferredKinds: provider.filters.preferredNearby, // seeker's picks first
        showHeader: false, // the section header + toggle sit above the card
      ),
      preferredLayerKeys: provider.filters.preferredNearby
          .map((k) => k.name)
          .take(6)
          .toSet(),
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
  _AskRentlyEntry({required this.property, this.title = ''});

  final RentalProperty property;
  final String title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Directionality(
      textDirection: Directionality.of(context),
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
                      l10n.propertyDetailScreen18b1f617,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l10n.propertyDetailScreen7e8504c2,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.slate500,
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
  _ImageGallery({
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

  // Reads the live page off the controller when it's attached (mid-drag or
  // just-settled), falling back to the `currentPage` prop otherwise (first
  // frame, or before the PageView has attached its scroll position).
  int _liveCurrentPage(List<PropertyMedia> media) {
    if (media.isEmpty) return 0;
    final live = controller.hasClients ? controller.page?.round() : null;
    return (live ?? currentPage).clamp(0, media.length - 1).toInt();
  }

  @override
  Widget build(BuildContext context) {
    final media = property.media;

    return Stack(
      fit: StackFit.expand,
      children: [
        media.isEmpty
            ? _ImageFallback(city: property.city)
            : PageView.builder(
                controller: controller,
                onPageChanged: onPageChanged,
                // Pre-builds the adjacent page before the user starts
                // dragging (default PageView only builds it once the drag
                // begins), so its SafeImage starts fetching/decoding ahead
                // of time instead of cold, mid-swipe.
                allowImplicitScrolling: true,
                itemCount: media.length,
                itemBuilder: (_, i) => SafeMedia(
                  media: media[i],
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  fallback: _ImageFallback(city: property.city),
                  videoMode: SafeVideoDisplayMode.playback,
                ),
              ),

        // Invisible tap zones for gallery navigation. The current-page check
        // is read lazily at tap time (not rebuilt per frame) — nothing here
        // needs to redraw while the controller scrolls.
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
                        if (_liveCurrentPage(media) > 0) {
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
                        if (_liveCurrentPage(media) < media.length - 1) {
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
                    color: AppColors.slate900,
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
                            color:
                                saved ? AppColors.primary : AppColors.slate900,
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
                        color: AppColors.slate900,
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
                  color: AppColors.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Text(
                  property.transactionLabel,
                  style: TextStyle(
                    color: AppColors.primary,
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

        // Carousel indicator dots — the one piece that actually needs to
        // redraw as the controller scrolls, so only this small subtree
        // listens to it (not the whole gallery Stack: buttons, gradient,
        // price badge etc. stay static and don't rebuild on drag frames).
        if (media.length > 1)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) => _CarouselDots(
                  count: media.length,
                  current: _liveCurrentPage(media),
                ),
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
            AppColors.cloud,
          ),
        BrokerPropertyTemplate.dashboardGlass => AppColors.border,
        BrokerPropertyTemplate.estateCard => AppColors.cloud,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _sections(context),
      ),
    );
  }

  /// The ordered list of section widgets (gallery thumbnails, facts,
  /// enrichment, match insight, owner, tour/media, description, features,
  /// reviews, map). Shared by [_ParitySections] (eager Column, for templates
  /// where this content is nested inside a decorative single-child wrapper
  /// that needs a measured child) and [_ParitySectionsSliver] (lazy
  /// SliverList, for templates where it sits directly in the CustomScrollView
  /// — only builds/lays out each section as it scrolls into view).
  List<Widget> _sections(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final media = property.media;
    final children = <Widget>[];

    // ── Highlights / market signals ───────────────────────────────────────
    if (_PropertySignalStrip.shouldShow(context, property)) {
      children.add(_PropertySignalStrip(property: property));
      children.add(const SizedBox(height: 24));
    }

    // ── Gallery thumbnails ────────────────────────────────────────────────
    if (media.isNotEmpty) {
      children.add(_header(
          l10n.propertyDetailScreenEed2fbf3, IconsaxPlusLinear.gallery));
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
    children.add(_header(
        l10n.propertyDetailScreen220d2733, IconsaxPlusLinear.building_3));
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
            Expanded(
                child: _header(l10n.propertyDetailScreenCb66c16b,
                    IconsaxPlusLinear.global)),
            GestureDetector(
              onTap: () async {
                await launchUrl(Uri.parse(property.url),
                    mode: LaunchMode.externalApplication);
              },
              child: Text(
                l10n.propertyDetailScreen5e4548cf,
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
          l10n.propertyDetailScreenAe561237(Uri.parse(property.url).host),
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
      children.add(_header(
          l10n.propertyDetailScreenDc721374, IconsaxPlusLinear.flash_1));
      children.add(_MatchInsightCard(property: property));
      children.add(const SizedBox(height: 26));
    }

    // ── Owner / contact (with verified badge inside the card) ─────────────
    children.add(_header(
        l10n.propertyDetailScreenC1a89075, IconsaxPlusLinear.profile_2user));
    children.add(_OwnerCard(property: property));
    children.add(const SizedBox(height: 26));

    // ── Virtual tours / media (360° + 3D scan) ────────────────────────────
    final has360 = property.hasPanoramaTour;
    // Show the 3D card if EITHER the legacy single-scan urls OR any viewable
    // room exists — a multi-room scan can carry rooms with empty legacy urls,
    // and the launcher already prefers viewableRooms, so gate on the same signal.
    final has3d = _scan3dGlbUrl(property) != null ||
        _scan3dSplatUrl(property) != null ||
        (property.model3d?.viewableRooms.isNotEmpty ?? false);
    children.add(_header(
      has360 || has3d
          ? l10n.propertyDetailScreenCd77cc3f
          : l10n.propertyDetailScreen2e98c1c0,
      IconsaxPlusLinear.video_play,
    ));

    final mediaCards = <Widget>[];
    if (has360) {
      mediaCards.add(_MediaTourCard(
        icon: Icons.threesixty_rounded,
        title: l10n.propertyDetailScreenCa52b1de,
        subtitle: l10n.propertyDetailScreen49f61379,
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
        title: l10n.propertyDetailScreen0774dd22,
        subtitle: l10n.propertyDetailScreen5364affd,
        branding: branding,
        surface: _cardSurface,
        onSurface: _onSurface,
        muted: _muted,
        onTap: () {
          // Multi-room scan → room-switcher; single scan → the classic viewer.
          final rooms = property.model3d?.viewableRooms ?? const [];
          if (rooms.length > 1) {
            Scan3dViewerScreen.openRooms(context, rooms,
                title: l10n.propertyDetailScreen5ba546d9);
          } else {
            Scan3dViewerScreen.open(
              context,
              meshGlbUrl: _scan3dGlbUrl(property),
              splatUrl: _scan3dSplatUrl(property),
              title: l10n.propertyDetailScreen5ba546d9,
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

    // ── Description ─────────────────────────────────────────────────────
    // Was captured (website's Ezra publisher flow always sends it) but had
    // no field in the app's model at all — silently dropped, never shown
    // anywhere. Now modeled (RentalProperty.description) and surfaced here.
    if (property.description.trim().isNotEmpty) {
      children.add(_header(l10n.propertyDetailScreenDescription,
          IconsaxPlusLinear.document_text));
      children.add(Text(
        property.description.trim(),
        style: TextStyle(
            fontSize: 14.5,
            height: 1.5,
            color: _onSurface.withValues(alpha: 0.85)),
      ));
      children.add(const SizedBox(height: 26));
    }

    // ── Key features / amenities ──────────────────────────────────────────
    if (property.features.isNotEmpty) {
      children.add(_header(
          l10n.propertyDetailScreen64680a66, IconsaxPlusLinear.flash_1));
      children.add(_FeatureWrap(features: property.features));
      children.add(const SizedBox(height: 26));
    }

    // ── Reviews ───────────────────────────────────────────────────────────
    if (reviews.isNotEmpty) {
      children.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
                child: _header(l10n.propertyDetailScreen1c5efd6c,
                    IconsaxPlusLinear.star_1)),
            Text(
              l10n.propertyDetailScreen16c30b46(reviews.length),
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
    children.add(
        _header(l10n.propertyDetailScreen26d0e7de, IconsaxPlusLinear.location));
    // All 21 layers stay visible and toggleable; the seeker's own "מקומות
    // בסביבה" picks start ON so an אתי-recommended listing opens with the
    // layers that matter to THEM already lit (capped so the map stays legible).
    final preferredLayerKeys = context
        .read<DatingProvider>()
        .filters
        .preferredNearby
        .map((k) => k.name)
        .take(6)
        .toSet();
    children.add(_MapSection(
      property: property,
      initialLayers: preferredLayerKeys.isEmpty ? null : preferredLayerKeys,
    ));

    return children;
  }
}

/// Lazy sliver counterpart of [_ParitySections] — same ordered sections
/// ([_ParitySections._sections]), but mounted/laid out only as they scroll
/// near the viewport instead of all at once on the first frame. Used by
/// templates whose parity block sits directly in a `CustomScrollView`
/// (not nested inside a decorative single-child wrapper — e.g. a
/// BackdropFilter/gradient panel — that needs a measured Column child).
class _ParitySectionsSliver extends StatelessWidget {
  const _ParitySectionsSliver({
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

  @override
  Widget build(BuildContext context) {
    final sections = _ParitySections(
      property: property,
      branding: branding,
      controller: controller,
      reviews: reviews,
      hasVirtualTour: hasVirtualTour,
      isLandlordPreview: isLandlordPreview,
      onShareTap: onShareTap,
      onTour: onTour,
      dark: dark,
    )._sections(context);

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => sections[index],
          childCount: sections.length,
        ),
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
    final l10n = AppLocalizations.of(context)!;
    final isProcessing = property.virtualTour?.isProcessing == true;
    final has360 = property.hasPanoramaTour;
    final hasVideo = property.videoUrls.isNotEmpty;
    final subtitle = has360
        ? l10n.propertyDetailScreenC7f1527f
        : hasVirtualTour
            ? l10n.propertyDetailScreen10c20d96
            : isProcessing
                ? l10n.propertyDetailScreenE41c38fa
                : l10n.propertyDetailScreenB4499910;

    return GestureDetector(
      onTap: onTour,
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
                        ? l10n.propertyDetailScreenCa52b1de
                        : hasVideo && !hasVirtualTour
                            ? l10n.propertyDetailScreenD60a9025
                            : l10n.propertyDetailScreen5f699c03,
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
  _Scan3dProcessingCard({
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
    final l10n = AppLocalizations.of(context)!;
    final title = widget.optimizing
        ? l10n.propertyDetailScreen84d6efd4
        : l10n.propertyDetailScreenAca86e76;
    final subtitle = widget.optimizing
        ? l10n.propertyDetailScreenAf2ce96d
        : l10n.propertyDetailScreenEd5f9651;
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
                    // Pre-builds the adjacent page before the drag starts
                    // (default PageView only builds it once dragging begins)
                    // so its SafeImage starts loading ahead of time.
                    allowImplicitScrolling: true,
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
            // Only the dots need to redraw as the controller scrolls — see
            // _ImageGallery.build for why the rest of this Stack stays static.
            if (media.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    final live =
                        controller.hasClients ? controller.page?.round() : null;
                    final safeCurrent = media.isEmpty
                        ? 0
                        : (live ?? currentPage)
                            .clamp(0, media.length - 1)
                            .toInt();
                    return _CarouselDots(
                        count: media.length, current: safeCurrent);
                  },
                ),
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
            sigmaX: PlatformFx.blurSigma(translucent ? 14 : 0),
            sigmaY: PlatformFx.blurSigma(translucent ? 14 : 0),
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
    final l10n = AppLocalizations.of(context)!;
    final facts = [
      _TemplateFact(IconsaxPlusLinear.building,
          l10n.propertyDetailScreenD886d07f(property.roomsLabel)),
      _TemplateFact(IconsaxPlusLinear.maximize_3,
          l10n.propertyDetailScreenFdb4eac7(property.sizeM2)),
      if (property.floor.isNotEmpty)
        _TemplateFact(
            IconsaxPlusLinear.layer,
            l10n.propertyDetailScreenD068bb57(
                floorLabel(property.floor, l10n))),
      if (property.condition.isNotEmpty)
        _TemplateFact(
            IconsaxPlusLinear.star, conditionLabel(property.condition, l10n)),
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
  _CarouselDots({required this.count, required this.current});
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
  _ImageFallback({required this.city});
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
          filter: ImageFilter.blur(
              sigmaX: PlatformFx.blurSigma(18),
              sigmaY: PlatformFx.blurSigma(18)),
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
  _OwnerCard({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final l10n = AppLocalizations.of(context)!;
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
            border: Border.all(color: AppColors.slate200),
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
                                ? [AppColors.primary, AppColors.primaryDark]
                                : [AppColors.slate600, AppColors.inkSoft],
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
                      // (No "verified" checkmark — `agencyListing` is self-declared,
                      // not a real verification signal.)
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
                            color: AppColors.slate900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          // `agencyListing` is self-declared, not verified — so
                          // don't claim "מאומת" (verified) here.
                          isAgency
                              ? l10n.propertyDetailScreen51146937
                              : l10n.propertyDetailScreenB49f4d60,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isAgency
                                ? AppColors.primary
                                : AppColors.slate500,
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
                        color: AppColors.yellowPale.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const RentlyIcon(
                            IconsaxPlusLinear.star_1,
                            size: 14,
                            color: AppColors.amberDark,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            avgRating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: AppColors.amberDeep,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l10n.propertyDetailScreen38b3ff8f,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppColors.slate600,
                  fontWeight: FontWeight.w500,
                ),
              ),

              // Real review quote bubble if available
              if (reviews.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.slate50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.slate100),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.format_quote_rounded,
                        size: 18,
                        color: AppColors.primary,
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
                            color: AppColors.slate600,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              const Divider(height: 1, color: AppColors.slate100),
              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => _showOwnerSheet(context, property, reviews),
                    child: Row(
                      children: [
                        RentlyIcon(IconsaxPlusLinear.profile_circle,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          l10n.propertyDetailScreen37735588,
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          l10n.propertyDetailScreen60c6ffbf(reviews.length),
                          style: const TextStyle(
                            color: AppColors.slate500,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  RentlyIcon(
                    IconsaxPlusLinear.arrow_left,
                    size: 14,
                    color: AppColors.primary,
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
                      children: [
                        RentlyIcon(IconsaxPlusLinear.house_2,
                            size: 16, color: AppColors.primary),
                        SizedBox(width: 6),
                        Text(
                          l10n.propertyDetailScreenB851d927,
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                    RentlyIcon(IconsaxPlusLinear.arrow_left,
                        size: 14, color: AppColors.primary),
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
  _MessageRequestButton({required this.property});
  final RentalProperty property;

  Future<void> _open(BuildContext context, DatingProvider provider) async {
    final l10n = AppLocalizations.of(context)!;
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
              Text(
                l10n.propertyDetailScreen20fdeb3f,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: l10n.propertyDetailScreenA60c8ada,
                  filled: true,
                  fillColor: AppColors.slate100,
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
                  child: Text(l10n.propertyDetailScreenDfe611d6,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (sent == true) {
      await provider.requestToMessage(property,
          note: controller.text, l10n: l10n);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(milliseconds: 2600),
          content: Text(l10n.propertyDetailScreenA8a4ed17),
        ));
      }
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<DatingProvider>();
    final already = provider.hasThreadForProperty(property.id);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: already ? null : () => _open(context, provider),
        icon: const RentlyIcon(IconsaxPlusLinear.message_text, size: 18),
        label: Text(already
            ? l10n.propertyDetailScreenD490b1b3
            : l10n.propertyDetailScreen35e6ba29),
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
  _OwnerProfileSheet({required this.property, required this.reviews});
  final RentalProperty property;
  final List<AppReview> reviews;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                        isAgency
                            ? l10n.propertyDetailScreenB5441c0d
                            : l10n.propertyDetailScreen3a3d66cf,
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
                              l10n.propertyDetailScreenF5211c9b(
                                  avgRating.toStringAsFixed(1), reviews.length),
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
  _SectionCardShell({
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
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.slate900,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        child,
        const SizedBox(height: 18),
        const Divider(height: 1, color: AppColors.slate100),
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
  _FeatureWrap({required this.features});
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
              color: AppColors.slate50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.slate200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  f,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.slate700,
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

/// Nearby-POI map layers, mirroring the web app's map layer picker
/// (rently-map-web FeaturePanel.tsx `LAYERS`) — same keys, labels, and colors.
class _MapLayer {
  const _MapLayer(
      this.key, this.label, this.color, this.poiCategory, this.icon);
  final String key;
  final String label;
  final Color color;
  // The category key the loaded POI data (see _MapSectionState._toggleLayer)
  // is grouped under.
  final String poiCategory;
  // Same icon NearbyPlacesCard uses for this category (nearby_places_card.dart
  // `_meta`) — keeps the two POI surfaces visually consistent.
  final IconData icon;
}

// All 21 NearbyKind categories (core/search/nearby_relevance.dart) — same
// icons NearbyPlacesCard uses per category (`_meta` above), one distinct
// color each so simultaneously-active layers stay visually separable.
const List<_MapLayer> _kMapLayers = [
  _MapLayer('schools', 'בתי ספר', Color(0xFF3B82F6), 'schools',
      IconsaxPlusLinear.teacher),
  _MapLayer('kindergartens', 'גני ילדים', Color(0xFFF97316), 'kindergartens',
      IconsaxPlusLinear.emoji_happy),
  _MapLayer('clinics', 'מרפאות', Color(0xFFEF4444), 'clinics',
      IconsaxPlusLinear.hospital),
  _MapLayer('pharmacies', 'בתי מרקחת', Color(0xFF14B8A6), 'pharmacies',
      IconsaxPlusLinear.health),
  _MapLayer('supermarkets', 'קניות', Color(0xFFF5A524), 'supermarkets',
      IconsaxPlusLinear.shopping_cart),
  _MapLayer(
      'parks', 'פארקים', Color(0xFF27AE60), 'parks', IconsaxPlusLinear.tree),
  _MapLayer('playgrounds', 'מגרשי משחקים', Color(0xFFEAB308), 'playgrounds',
      IconsaxPlusLinear.game),
  _MapLayer(
      'dining', 'אוכל', Color(0xFFFF5A67), 'dining', IconsaxPlusLinear.reserve),
  _MapLayer(
      'gyms', 'חדרי כושר', Color(0xFF8B5CF6), 'gyms', IconsaxPlusLinear.weight),
  _MapLayer('nightlife', 'חיי לילה', Color(0xFFDB2777), 'nightlife',
      IconsaxPlusLinear.cup),
  _MapLayer('synagogues', 'בתי כנסת', Color(0xFF7C3AED), 'synagogues',
      IconsaxPlusLinear.buildings),
  _MapLayer('culture', 'תרבות', Color(0xFFEC4899), 'culture',
      IconsaxPlusLinear.gallery),
  _MapLayer('hospitals', 'בתי חולים', Color(0xFFDC2626), 'hospitals',
      IconsaxPlusLinear.heart),
  _MapLayer(
      'transit', 'תחבורה', Color(0xFF2C64E3), 'transit', IconsaxPlusLinear.bus),
  _MapLayer('worship', 'בתי תפילה', Color(0xFF9333EA), 'worship',
      IconsaxPlusLinear.courthouse),
  _MapLayer(
      'pools', 'בריכות', Color(0xFF06B6D4), 'pools', IconsaxPlusLinear.drop),
  _MapLayer('dogParks', 'גינות כלבים', Color(0xFFA16207), 'dogParks',
      IconsaxPlusLinear.pet),
  _MapLayer('vets', 'וטרינרים', Color(0xFF0D9488), 'vets',
      IconsaxPlusLinear.lifebuoy),
  _MapLayer('bikeShare', 'אופניים', Color(0xFF65A30D), 'bikeShare',
      IconsaxPlusLinear.routing),
  _MapLayer('coworking', 'קוורקינג', Color(0xFF4B5563), 'coworking',
      IconsaxPlusLinear.briefcase),
  _MapLayer(
      'parking', 'חניה', Color(0xFF1F2937), 'parking', IconsaxPlusLinear.car),
  _MapLayer('rail', 'תחנות רכבת', Color(0xFF0EA5E9), 'rail',
      IconsaxPlusLinear.routing),
  _MapLayer('airQuality', 'איכות אוויר', Color(0xFF14B8A6), 'airQuality',
      IconsaxPlusLinear.wind_2),
];

/// "מקומות בקרבת הדירה" — one section, two views behind a segmented toggle:
/// רשימה (the existing NearbyPlacesCard) or מפה (the same _MapSection used at
/// the bottom of the page, whose chip strip IS the tag picker — same design).
class _NearbySection extends StatefulWidget {
  const _NearbySection({
    required this.property,
    required this.listView,
    required this.preferredLayerKeys,
  });
  final RentalProperty property;
  final Widget listView;
  final Set<String> preferredLayerKeys;

  @override
  State<_NearbySection> createState() => _NearbySectionState();
}

class _NearbySectionState extends State<_NearbySection> {
  bool _mapMode = false;

  Widget _segment(
      {required bool selected,
      required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 15, color: selected ? Colors.white : AppColors.slate500),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppColors.slate500,
              )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l10n.nearbyPlacesCard29364e0f,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
            ),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.primaryLight2,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _segment(
                  selected: !_mapMode,
                  icon: IconsaxPlusLinear.textalign_right,
                  label: l10n.nearbyToggleList,
                  onTap: () => setState(() => _mapMode = false),
                ),
                _segment(
                  selected: _mapMode,
                  icon: IconsaxPlusLinear.map_1,
                  label: l10n.nearbyToggleMap,
                  onTap: () => setState(() => _mapMode = true),
                ),
              ]),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Map mode reuses the page's map section 1:1 — including its layer-chip
        // strip, which serves as the tag picker (same design, same behavior).
        if (_mapMode)
          _MapSection(
            property: widget.property,
            initialLayers: widget.preferredLayerKeys.isEmpty
                ? null
                : widget.preferredLayerKeys,
          )
        else
          widget.listView,
      ],
    );
  }
}

class _MapSection extends StatefulWidget {
  _MapSection({
    required this.property,
    this.fullscreen = false,
    this.initialLayers,
  });
  final RentalProperty property;
  // Fullscreen variant: fills its parent, no expand button, ready immediately.
  final bool fullscreen;
  // Layers to start with (carried over when expanding to fullscreen).
  final Set<String>? initialLayers;

  @override
  State<_MapSection> createState() => _MapSectionState();
}

class _MapSectionState extends State<_MapSection> {
  bool _ready = false;
  bool _layersOpen = false;
  bool _loadingPois = false;
  Map<String, List<NearbyPlace>>? _poiData;
  final Set<String> _activeLayers = {};
  final MapController _mapController = MapController();
  // The POI dot the user last tapped, with the layer it belongs to (for the
  // popup's color/label) — null when no popup is showing.
  (NearbyPlace place, _MapLayer layer)? _selectedPoi;

  @override
  void initState() {
    super.initState();
    final carried = widget.initialLayers;
    if (carried != null) _activeLayers.addAll(carried);
    if (widget.fullscreen) {
      // Fullscreen is user-initiated — no need to defer, and the carried-over
      // layers need their POI data loaded in this fresh state object.
      _ready = true;
      if (_activeLayers.isNotEmpty) unawaited(_ensurePoisLoaded());
      return;
    }
    // Defer the FlutterMap (widget init + OpenStreetMap tile fetch) off the
    // page-open critical path — building it eagerly on every listing open was a
    // main cause of the "delay entering an apartment page". The map is below the
    // fold, so it fills in a moment after the page has slid in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        setState(() => _ready = true);
        // Preferred layers start ON — their POI dots need data to show.
        if (_activeLayers.isNotEmpty) unawaited(_ensurePoisLoaded());
      });
    });
  }

  /// Toggles a POI layer on/off, mirroring the web app's `onToggleLayer`.
  ///
  /// Data source: the BUNDLED gov+OSM POI index (`IsraelGeoIndex`), not the
  /// live Overpass API. Overpass was the original choice (same source the
  /// website's layer picker uses) but proved unreliable in practice — a live
  /// test hit HTTP 504 on the primary endpoint and a 30s client timeout on
  /// the fallback mirror, i.e. the public, rate-limited Overpass service can
  /// simply fail to answer a heavy (1km, multi-category) query in reasonable
  /// time. `IsraelGeoIndex` is a local asset, already used for these exact
  /// categories elsewhere in the app (`NearbyPlacesCard`) — no network
  /// dependency, so it can't have this failure mode.
  Future<void> _toggleLayer(String key) async {
    setState(() {
      if (_activeLayers.contains(key)) {
        _activeLayers.remove(key);
        // Don't leave a popup describing a dot that just disappeared.
        if (_selectedPoi != null && _selectedPoi!.$2.key == key) {
          _selectedPoi = null;
        }
      } else {
        _activeLayers.add(key);
      }
    });
    if (!_activeLayers.contains(key)) return;
    await _ensurePoisLoaded();
  }

  Future<void> _ensurePoisLoaded() async {
    if (_poiData != null || _loadingPois) return;
    setState(() => _loadingPois = true);
    // Idempotent loaders — no-op if already loaded (e.g. NearbyPlacesCard
    // further down this same page already triggered them). Same 5 calls
    // NearbyPlacesCard uses to cover all 21 NearbyKind categories.
    await Future.wait([
      IsraelGeoIndex.loadSchools(),
      IsraelGeoIndex.loadParks(),
      IsraelGeoIndex.loadClinics(),
      IsraelGeoIndex.loadSupermarkets(),
      IsraelGeoIndex.loadLifestylePois(),
    ]);
    if (!mounted) return;
    final lat = widget.property.lat;
    final lon = widget.property.lon;
    final data = <String, List<NearbyPlace>>{
      'schools': IsraelGeoIndex.schoolsWithin(lat, lon, km: 1.0, cap: 40),
      'kindergartens':
          IsraelGeoIndex.kindergartensWithin(lat, lon, km: 1.0, cap: 40),
      'clinics': IsraelGeoIndex.clinicsWithin(lat, lon, km: 3.0, cap: 40),
      'pharmacies': IsraelGeoIndex.pharmaciesWithin(lat, lon, km: 1.0, cap: 40),
      'supermarkets':
          IsraelGeoIndex.supermarketsWithin(lat, lon, km: 1.0, cap: 40),
      'parks': IsraelGeoIndex.parksWithin(lat, lon, km: 1.0, cap: 40),
      'playgrounds':
          IsraelGeoIndex.playgroundsWithin(lat, lon, km: 1.0, cap: 40),
      'dining': IsraelGeoIndex.diningWithin(lat, lon, km: 1.0, cap: 40),
      'gyms': IsraelGeoIndex.gymsWithin(lat, lon, km: 1.0, cap: 40),
      'nightlife':
          IsraelGeoIndex.nightlifeVenuesWithin(lat, lon, km: 1.0, cap: 40),
      'synagogues': IsraelGeoIndex.synagoguesWithin(lat, lon, km: 1.0, cap: 40),
      'culture': IsraelGeoIndex.cultureWithin(lat, lon, km: 1.0, cap: 40),
      'hospitals': IsraelGeoIndex.hospitalsWithin(lat, lon, km: 5.0, cap: 40),
      'transit': IsraelGeoIndex.transitStopsWithin(lat, lon, km: 1.0, cap: 40),
      'worship': IsraelGeoIndex.worshipWithin(lat, lon, km: 1.0, cap: 40),
      'pools': IsraelGeoIndex.poolsWithin(lat, lon, km: 1.0, cap: 40),
      'dogParks': IsraelGeoIndex.dogParksWithin(lat, lon, km: 1.0, cap: 40),
      'vets': IsraelGeoIndex.vetsWithin(lat, lon, km: 1.0, cap: 40),
      'bikeShare': IsraelGeoIndex.bikeShareWithin(lat, lon, km: 1.0, cap: 40),
      'coworking': IsraelGeoIndex.coworkingWithin(lat, lon, km: 1.0, cap: 40),
      'parking': IsraelGeoIndex.parkingWithin(lat, lon, km: 1.0, cap: 40),
      // Far-relevance categories get a wider radius — 1km showed zero dots
      // for layers whose list card uses 5km.
      'rail': IsraelGeoIndex.railStationsWithin(lat, lon, km: 5.0, cap: 40),
      'airQuality':
          IsraelGeoIndex.airQualityStationsWithin(lat, lon, km: 5.0, cap: 40),
    };
    if (kDebugMode) {
      debugPrint('_MapSection: loaded bundled POIs → '
          '${data.map((k, v) => MapEntry(k, v.length))}');
    }
    setState(() {
      _poiData = data;
      _loadingPois = false;
    });
  }

  List<Marker> _poiMarkers() {
    final data = _poiData;
    if (data == null || _activeLayers.isEmpty) return const [];
    final markers = <Marker>[];
    for (final layer in _kMapLayers) {
      if (!_activeLayers.contains(layer.key)) continue;
      final places = data[layer.poiCategory];
      if (places == null) continue;
      // Nearest-first list; cap so a dense city centre doesn't flood the
      // tiny inline map with hundreds of dots.
      for (final p in places.take(40)) {
        final isSelected =
            _selectedPoi != null && identical(_selectedPoi!.$1, p);
        final size = isSelected ? 30.0 : 24.0;
        markers.add(Marker(
          point: LatLng(p.lat, p.lon),
          width: size,
          height: size,
          child: GestureDetector(
            // Tapping a pin opens the info popup instead of letting the tap
            // fall through to the map's own pan/zoom gesture handling.
            onTap: () => setState(() => _selectedPoi = (p, layer)),
            child: Container(
              decoration: BoxDecoration(
                color: layer.color,
                shape: BoxShape.circle,
                // Spec: 3px white stroke + light drop shadow on all POI dots.
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 6,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Icon(layer.icon,
                  color: Colors.white, size: isSelected ? 16 : 13),
            ),
          ),
        ));
      }
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final property = widget.property;
    final body = Stack(
          fit: StackFit.expand,
          children: [
            if (_ready)
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: LatLng(property.lat, property.lon),
                  initialZoom: 15,
                  // Interactive (drag/pinch-zoom/double-tap-zoom, no rotate —
                  // keeps north-up so it stays legible at this small size).
                  // This card lives inside the page's outer scroll view;
                  // flutter_map's own gesture recognizer only claims pointer
                  // events that start ON the map itself, so a drag starting
                  // outside the map card still scrolls the page normally —
                  // the same trade-off any embedded interactive map makes.
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.drag |
                        InteractiveFlag.flingAnimation |
                        InteractiveFlag.pinchZoom |
                        InteractiveFlag.pinchMove |
                        InteractiveFlag.doubleTapZoom,
                  ),
                  // Tapping empty map space dismisses the POI popup (tapping
                  // a dot itself is handled by the marker's own
                  // GestureDetector, which wins the gesture arena first).
                  onTap: (_, __) {
                    if (_selectedPoi != null) {
                      setState(() => _selectedPoi = null);
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.rentch.app',
                  ),
                  const SimpleAttributionWidget(
                    source: Text('OpenStreetMap'),
                  ),
                  MarkerLayer(markers: _poiMarkers()),
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
                            boxShadow: [
                              BoxShadow(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.27),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4)),
                            ],
                          ),
                          child: const RentlyIcon(IconsaxPlusLinear.building,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            else
              ColoredBox(
                color: AppColors.border,
                child: Center(
                  child: RentlyIcon(IconsaxPlusLinear.map_1,
                      color: AppColors.primary, size: 30),
                ),
              ),
            // "Open in maps" hint pill + recenter button — hidden while the
            // POI popup is showing (same bottom-right corner, would overlap).
            if (_selectedPoi == null)
              Positioned(
                bottom: 12,
                right: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!widget.fullscreen) ...[
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            fullscreenDialog: true,
                            builder: (_) => Scaffold(
                              appBar: AppBar(
                                title: Text(
                                    AppLocalizations.of(context)!
                                        .propertyDetailScreen26d0e7de),
                              ),
                              body: _MapSection(
                                property: widget.property,
                                fullscreen: true,
                                initialLayers: {..._activeLayers},
                              ),
                            ),
                          ),
                        ),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.62),
                            shape: BoxShape.circle,
                          ),
                          child: const RentlyIcon(IconsaxPlusLinear.maximize_4,
                              size: 14, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    GestureDetector(
                      onTap: () => _mapController.move(
                          LatLng(property.lat, property.lon), 15),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          shape: BoxShape.circle,
                        ),
                        child: RentlyIcon(IconsaxPlusLinear.gps,
                            size: 14, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _openInMaps(property.lat, property.lon),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const RentlyIcon(IconsaxPlusLinear.export_2,
                                size: 13, color: Colors.white),
                            const SizedBox(width: 5),
                            Text(
                              l10n.propertyDetailScreenDf4787e7,
                              style: const TextStyle(
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
            // Selected-POI popup — colored dot + name + category, with a
            // button to open THAT point in Google Maps, and a close (x).
            if (_selectedPoi != null)
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _selectedPoi!.$2.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _selectedPoi!.$1.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                            Text(
                              _selectedPoi!.$2.label,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.slate500,
                              ),
                            ),
                            Text(
                              _distanceAndWalkLabel(l10n, _selectedPoi!.$1),
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.slate500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _openInMaps(
                            _selectedPoi!.$1.lat, _selectedPoi!.$1.lon),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: RentlyIcon(IconsaxPlusLinear.export_2,
                              size: 15, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => setState(() => _selectedPoi = null),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            shape: BoxShape.circle,
                          ),
                          child: const RentlyIcon(
                              IconsaxPlusLinear.close_circle,
                              size: 15,
                              color: AppColors.slate500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Layers toggle — glass pill with icon + label, top-start corner.
            Positioned(
              top: 12,
              left: 12,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: GestureDetector(
                    onTap: () => setState(() => _layersOpen = !_layersOpen),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _layersOpen
                            ? AppColors.primary.withValues(alpha: 0.85)
                            : Colors.black.withValues(alpha: 0.38),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RentlyIcon(IconsaxPlusLinear.layer,
                              size: 15, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            l10n.propertyDetailScreenAddLayers,
                            style: const TextStyle(
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
              ),
            ),
            // Layer chips panel — same 4 layers/colors as the web
            // FeaturePanel, adapted to a compact glass strip for this
            // inline card.
            if (_layersOpen)
              Positioned(
                top: 52,
                left: 12,
                right: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: GestureDetector(
                      // Absorb taps so they don't fall through to the outer
                      // "open in maps" GestureDetector.
                      onTap: () {},
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.38),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_loadingPois)
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 6, right: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 1.6,
                                          color: Colors.white70),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      l10n.propertyDetailScreenLoadingPois,
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10.5),
                                    ),
                                  ],
                                ),
                              ),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final layer in _kMapLayers) ...[
                                    _MapLayerChip(
                                      layer: layer,
                                      active: _activeLayers.contains(layer.key),
                                      onTap: () => _toggleLayer(layer.key),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
    if (widget.fullscreen) return body;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(height: 280, child: body),
    );
  }

  /// "350 מ׳ · 4 דק׳ הליכה"-style label — straight-line distance from the
  /// property to a POI, plus an estimated walk time at ~5km/h.
  String _distanceAndWalkLabel(AppLocalizations l10n, NearbyPlace place) {
    final meters = const Distance().as(
      LengthUnit.Meter,
      LatLng(widget.property.lat, widget.property.lon),
      LatLng(place.lat, place.lon),
    );
    final distanceLabel = meters < 1000
        ? l10n.propertyDetailScreenDistanceMeters((meters / 10).round() * 10)
        : l10n
            .propertyDetailScreenDistanceKm((meters / 1000).toStringAsFixed(1));
    final minutes = max(1, (meters / 83.3).round());
    return '$distanceLabel · ${l10n.propertyDetailScreenWalkMinutes(minutes)}';
  }

  Future<void> _openInMaps(double lat, double lon) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lon',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// A single map-layer toggle pill: colored dot + label, filled-white when
/// active / translucent-glass when inactive — matches the web app's
/// FeaturePanel layer chips (rently-map-web), scaled down for this card.
class _MapLayerChip extends StatelessWidget {
  const _MapLayerChip({
    required this.layer,
    required this.active,
    required this.onTap,
  });
  final _MapLayer layer;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(layer.icon,
                size: 14, color: active ? layer.color : Colors.white),
            const SizedBox(width: 5),
            Text(
              layer.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: active ? Colors.black : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  _BottomBar({
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
    final l10n = AppLocalizations.of(context)!;
    final isProcessing = property.virtualTour?.isProcessing == true;
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: PlatformFx.blurSigma(18), sigmaY: PlatformFx.blurSigma(18)),
        child: Container(
          padding: EdgeInsets.fromLTRB(
              20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            border: const Border(
              top: BorderSide(
                color: AppColors.slate200,
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
                          icon: const RentlyIcon(IconsaxPlusLinear.edit,
                              size: 18),
                          label: Text(l10n.propertyDetailScreen9e8d9316,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.slate900,
                            side: const BorderSide(color: AppColors.slate200),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: onLike,
                          icon: const RentlyIcon(IconsaxPlusLinear.heart,
                              size: 18),
                          label: Text(l10n.propertyDetailScreen38bf5edd,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.slate900,
                            side: const BorderSide(color: AppColors.slate200),
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
                              ? l10n.propertyDetailScreen5f699c03
                              : isProcessing
                                  ? l10n.propertyDetailScreen18078153
                                  : (isLandlordPreview
                                      ? l10n.propertyDetailScreen567a5b29
                                      : l10n.propertyDetailScreenE895a9f6),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
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
  _TourUnavailableSheet({required this.property});

  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                ? l10n.propertyDetailScreen5e0a5dc3
                : isProcessing
                    ? l10n.propertyDetailScreen00ae4acb
                    : hasSource
                        ? l10n.propertyDetailScreenE55088ee
                        : l10n.propertyDetailScreen19a76d77,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasFailed
                ? l10n.propertyDetailScreenA692c8ad
                : isProcessing
                    ? _processingCopy(context, tour)
                    : hasSource
                        ? l10n.propertyDetailScreen737db867
                        : l10n.propertyDetailScreen6f8a3ed4,
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
              _processingEta(context, tour),
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
                  label: Text(l10n.propertyDetailScreen55247199),
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
                  label: Text(l10n.propertyDetailScreenE53b7e24),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _processingCopy(BuildContext context, PropertyVirtualTour? tour) {
    final l10n = AppLocalizations.of(context)!;
    final stage = tour?.processingStage.trim().toLowerCase() ?? '';
    final progress = tour?.processingProgress;
    if (progress != null) {
      return l10n.propertyDetailScreen1b33c853(progress);
    }
    return switch (stage) {
      'pending' => l10n.propertyDetailScreen57f60266,
      'staging' => l10n.propertyDetailScreen910fa358,
      'complete' => l10n.propertyDetailScreen8915c338,
      _ => l10n.propertyDetailScreen2e691011,
    };
  }

  String _processingEta(BuildContext context, PropertyVirtualTour? tour) {
    final l10n = AppLocalizations.of(context)!;
    final stage = tour?.processingStage.trim().toLowerCase() ?? '';
    return switch (stage) {
      'pending' => l10n.propertyDetailScreen45f39647,
      'staging' => l10n.propertyDetailScreen1aa87a41,
      _ => l10n.propertyDetailScreenDc5803b6,
    };
  }
}

class _VirtualTourScreen extends StatelessWidget {
  const _VirtualTourScreen({required this.property});

  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.view_in_ar_rounded,
                              size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              l10n.propertyDetailScreen5f699c03,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
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
                    Text(
                      l10n.propertyDetailScreen105df502,
                      style: const TextStyle(
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
  _InteractiveTourScreen({required this.property, required this.tour});

  final RentalProperty property;
  final PropertyVirtualTour tour;

  // Luma virtual-staging returns an AI image, not an interactive 3D asset.
  // Detect that so we render it inline as a visualization instead of the
  // "interactive tour" placeholder (which is meant for video/real-3D viewers).
  bool get _isImageVisualization {
    final f = tour.format.trim().toLowerCase();
    if (f == 'image') return true;
    if (f == 'video' ||
        f == 'glb' ||
        f == 'gltf' ||
        f == 'usdz' ||
        f == 'splat' ||
        f == 'mesh' ||
        f == '3d') {
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
    final l10n = AppLocalizations.of(context)!;
    final quality = tour.qualityScore == null
        ? null
        : (tour.qualityScore! * 100).clamp(0, 100).round();
    return Scaffold(
      backgroundColor: AppColors.ink,
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
              Text(
                l10n.propertyDetailScreen8f880283,
                style: const TextStyle(
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
                      label: l10n.propertyDetailScreen5ec26848(quality),
                    ),
                  if (tour.downloadUrl.trim().isNotEmpty)
                    _DarkMetricChip(
                      icon: IconsaxPlusLinear.document_cloud,
                      label: l10n.propertyDetailScreen47a54d83,
                    ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openViewer(context, tour.viewerUrl),
                  icon: const RentlyIcon(IconsaxPlusLinear.export_2),
                  label: Text(l10n.propertyDetailScreen4e4ee34f),
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
    final l10n = AppLocalizations.of(context)!;
    final rawUrl = tour.previewImageUrl.trim().isNotEmpty
        ? tour.previewImageUrl.trim()
        : tour.viewerUrl.trim();
    final url = MediaCdn.url(rawUrl);
    return Scaffold(
      backgroundColor: AppColors.ink,
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
                          errorBuilder: (_, __, ___) => Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.broken_image_rounded,
                                    color: Colors.white38, size: 54),
                                const SizedBox(height: 10),
                                Text(l10n.propertyDetailScreenB29bd206,
                                    style:
                                        const TextStyle(color: Colors.white60)),
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
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome_rounded,
                              size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(l10n.propertyDetailScreenEef6e71b,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12)),
                          ),
                        ],
                      ),
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
  _AffordabilityStrip({
    required this.property,
    required this.monthlyIncome,
  });

  final RentalProperty property;
  final int? monthlyIncome;

  static const _bandColors = <RentBand, Color>{
    RentBand.comfortable: AppColors.greenBright,
    RentBand.stretched: AppColors.amber,
    RentBand.high: AppColors.coral,
    RentBand.unknown: AppColors.slate500,
  };

  Map<RentBand, String> _bandLabels(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return <RentBand, String>{
      RentBand.comfortable: l10n.propertyDetailScreenB94d2093,
      RentBand.stretched: l10n.propertyDetailScreen6d51cdeb,
      RentBand.high: l10n.propertyDetailScreen8d3cefa5,
      RentBand.unknown: l10n.propertyDetailScreenE0def62e,
    };
  }

  static String _lineItemLabel(AppLocalizations l10n, CostLineKind kind) {
    switch (kind) {
      case CostLineKind.firstMonthRent:
        return l10n.affordability5e721167;
      case CostLineKind.deposit:
        return l10n.affordability26a740b7;
      case CostLineKind.brokerFee:
        return l10n.affordabilityFc095a4e;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final result = Affordability.assess(
      monthlyRent: property.price,
      monthlyIncome: monthlyIncome,
    );
    final color = _bandColors[result.band]!;
    final ratioPct = result.rentToIncomePercent;
    final bandLabels = _bandLabels(context);

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
              RentlyIcon(IconsaxPlusLinear.wallet_money,
                  size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.band == RentBand.unknown
                      ? l10n.propertyDetailScreenE1354b80
                      : '${bandLabels[result.band]}'
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
                      _lineItemLabel(l10n, item.kind),
                      style: const TextStyle(
                        color: AppColors.slate600,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '₪${item.amount}',
                    style: const TextStyle(
                      color: AppColors.slate900,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 16, color: AppColors.slate200),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.propertyDetailScreenB146c814,
                style: const TextStyle(
                  color: AppColors.slate900,
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
                side: const BorderSide(color: AppColors.slate200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: RentlyIcon(IconsaxPlusLinear.shield_tick,
                  size: 16, color: AppColors.primary),
              label: Text(
                l10n.propertyDetailScreen4afd38ca,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PropertySignalStrip extends StatelessWidget {
  _PropertySignalStrip({required this.property});

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
    final l10n = AppLocalizations.of(context)!;
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
            label: l10n.propertyDetailScreenB2e36464(signals.views),
            color: AppColors.greenBright,
          ),
        if (signals.likes > 0)
          _PropertySignalChip(
            icon: IconsaxPlusLinear.heart,
            label: l10n.propertyDetailScreenA9d0dba3(signals.likes),
            color: AppColors.coral,
          ),
        if (property.isVerifiedListing)
          GestureDetector(
            onTap: () => VerificationInfoSheet.show(context),
            child: _PropertySignalChip(
              icon: IconsaxPlusLinear.verify,
              label: l10n.propertyDetailScreen220a89be,
              color: AppColors.primary,
              showInfoHint: true,
            ),
          ),
        if (property.isNewListing)
          SignalStripPulse(
            child: _PropertySignalChip(
              icon: IconsaxPlusLinear.flash_1,
              label: l10n.propertyDetailScreenD5424d20,
              color: AppColors.primary,
            ),
          ),
        if (signals.liveViewers > 0)
          SignalStripPulse(
            child: _PropertySignalChip(
              icon: IconsaxPlusLinear.eye,
              label: signals.liveViewers == 1
                  ? l10n.propertyDetailScreen67fb588b
                  : l10n.propertyDetailScreen479025fb(signals.liveViewers),
              color: AppColors.greenBright,
            ),
          ),
        if (likesToday > 0)
          SignalStripPulse(
            child: _PropertySignalChip(
              icon: IconsaxPlusLinear.heart,
              label: l10n.propertyDetailScreenAb15e1c6(likesToday),
              color: AppColors.coral,
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
    final l10n = AppLocalizations.of(context)!;
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
                  l10n.propertyDetailScreenB50b3974,
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
                  l10n.propertyDetailScreen451ffaea,
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
                  property.floor.isNotEmpty
                      ? floorLabel(property.floor, l10n)
                      : '-',
                  l10n.propertyDetailScreen047e630b,
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
                  property.condition.isNotEmpty
                      ? conditionLabel(property.condition, l10n)
                      : l10n.propertyDetailScreen3e20e30e,
                  l10n.propertyDetailScreen357b4923,
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
                  hasParking
                      ? l10n.propertyDetailScreen1f70207b
                      : l10n.propertyDetailScreenEa12a4ba,
                  l10n.propertyDetailScreen3ac08c81,
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
                  hasElevator
                      ? l10n.propertyDetailScreen1f70207b
                      : l10n.propertyDetailScreenEa12a4ba,
                  l10n.propertyDetailScreen8d058056,
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
        border: Border.all(color: AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.slate500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.slate900,
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
              color: AppColors.slate500,
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
          final l10n = AppLocalizations.of(context)!;
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
              border: Border.all(color: AppColors.slate200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.slate200,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.slate900,
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
                              color: AppColors.slate900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            l10n.propertyDetailScreen7563e7f9,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.slate500,
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
                        color: AppColors.yellowPale.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const RentlyIcon(
                            IconsaxPlusLinear.star_1,
                            size: 12,
                            color: AppColors.amberDark,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            review.rating.toString(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.amberDeep,
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
                      color: AppColors.slate600,
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
  _MatchInsightDropdown({required this.property});
  final RentalProperty property;

  @override
  State<_MatchInsightDropdown> createState() => _MatchInsightDropdownState();
}

class _MatchInsightDropdownState extends State<_MatchInsightDropdown> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Icon(IconsaxPlusLinear.flash_1,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.propertyDetailScreen48abdfae,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.slate900,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: AppColors.slate100,
                  shape: BoxShape.circle,
                ),
                child: AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    IconsaxPlusLinear.arrow_down_1,
                    size: 16,
                    color: AppColors.slate500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
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
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 220),
        ),
        const SizedBox(height: 18),
        const Divider(height: 1, color: AppColors.slate100),
      ],
    );
  }
}

class _MatchInsightCard extends StatelessWidget {
  _MatchInsightCard({required this.property});
  final RentalProperty property;

  (Color, Color) _tierColors(MatchTier tier) => switch (tier) {
        MatchTier.perfect => (AppColors.green, AppColors.border),
        MatchTier.excellent => (AppColors.primary, AppColors.primaryLight2),
        MatchTier.good => (AppColors.blue, AppColors.border),
        MatchTier.fair => (AppColors.amberDark, AppColors.warningBg),
        MatchTier.weak => (AppColors.textSecondary, AppColors.slate100),
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
    final l10n = AppLocalizations.of(context)!;
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
                      ? l10n.propertyDetailScreenF83ca4dc
                      : l10n.propertyDetailScreen98f6f9b2,
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
                    size: 16, color: AppColors.green),
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
