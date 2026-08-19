import 'dart:async';
import 'package:dating_app/core/ui/platform_fx.dart';
import 'package:dating_app/core/utils/helpers/property_label_helper.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/search/nearby_relevance.dart' show NearbyKind;
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/services/assistant_service.dart';
import 'package:dating_app/core/services/behavior_insights_service.dart';
import 'package:dating_app/core/services/event_service.dart';
import 'package:dating_app/core/services/notification_service.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/data/repositories/saved_search_repository.dart';
import 'package:dating_app/presentation/features/discover/action_button.dart';
import 'package:dating_app/presentation/features/discover/profile_card.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:dating_app/presentation/screens/saved_properties_screen.dart';
import 'package:dating_app/presentation/screens/saved_searches_screen.dart';
import 'package:dating_app/presentation/screens/notifications_screen.dart';
import 'package:dating_app/data/models/app_notification.dart';
import 'package:dating_app/presentation/widgets/gamification/fomo_widgets.dart';
import 'package:dating_app/presentation/widgets/recommended_for_you_strip.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:dating_app/main.dart' show markInAppBack;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

enum DiscoverTab { discover, forYou }

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen>
    with WidgetsBindingObserver {
  DiscoverTab _selectedTab = DiscoverTab.forYou;
  int _lastSwipesSignal = 0;

  // ── Natural-language search (the hero bar) ────────────────────────────────
  // Reuses the existing extract→search pipeline: server Gemini extract +
  // on-device SmartSearch parse → SearchQuery → mapped onto the live filters
  // so results land straight in the discover deck.
  final _nlController = TextEditingController();
  final _nlAssistant = AssistantService();
  bool _nlBusy = false;
  String? _nlSummary; // the understood criteria, shown back to the user
  // The NL search bar is collapsed by default (opens from the top-left search
  // icon) so it never shrinks the swipe card — the card keeps its full size.
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Run once on entry too (covers cold start), not just on later resumes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSavedSearches();
      // Prime the collaborative-filtering picks that power the "מומלץ בשבילך"
      // strip under the search bar. Fail-soft in the provider — never blocks or
      // errors the UI, and leaves the strip hidden if nothing comes back.
      if (mounted) {
        context.read<DatingProvider>().loadCfRecommendations();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nlController.dispose();
    super.dispose();
  }

  /// The hero NL search: takes the user's free Hebrew text, runs it through the
  /// same extract→parse pipeline the AI-search tab uses, then translates the
  /// resulting [SearchQuery] into the live [SearchFilters] so the discover deck
  /// re-filters + re-ranks to match. Fail-soft — a model outage still parses
  /// on-device, and any error just leaves the current results untouched.
  Future<void> _runNlSearch(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _nlBusy) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final provider = context.read<DatingProvider>();
    setState(() => _nlBusy = true);

    // Etti's COMPLEX ALGORITHM, zero AI tokens: run the full on-device
    // SmartSearch parse only (GovData locality resolution, budget/rooms/features,
    // intents, inference rules like <100k→rent). No LLM round-trip → instant + free.
    // The deck then re-ranks (community-fit) over the structured query below.
    final query = SmartSearch.parse(text);

    if (!mounted) return;
    if (query.isEmpty) {
      setState(() {
        _nlBusy = false;
        _nlSummary = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 2600),
        content: Text(AppLocalizations.of(context)!.discoverScreenE5a47f62),
      ));
      return;
    }

    // 3) Map the NL query onto the live filters → discover deck re-ranks.
    final next = _filtersFromQuery(provider.filters, query);
    await provider.updateFilters(next);

    if (!mounted) return;
    setState(() {
      _nlBusy = false;
      // Make the search AREA explicit so "אזור" is never ambiguous: we show the
      // city + that nearby areas are included (the engine widens to the metro
      // ring when the exact city is sparse).
      final city = query.city?.trim() ?? '';
      final l10n = AppLocalizations.of(context)!;
      _nlSummary = city.isEmpty
          ? query.describe(l10n)
          : l10n.discoverScreenC5c195f6(query.describe(l10n), city);
    });
  }

  /// Translates a parsed [SearchQuery] into a [SearchFilters] patch over the
  /// current filters (so anything the NL query didn't mention is preserved).
  SearchFilters _filtersFromQuery(SearchFilters base, SearchQuery q) {
    return base.copyWith(
      // Do NOT dump the whole sentence into `query` — the deck hard-requires
      // searchableText.contains(query), so a full sentence like "3 חדרים בתל
      // אביב עד 6000" matches nothing and empties the deck. The structured
      // fields below carry the intent; only a parsed neighbourhood (which IS in
      // searchableText) is kept as a keyword.
      query: q.neighborhood ?? '',
      city: q.city,
      minBudget: q.minPrice,
      maxBudget: q.maxPrice,
      minRooms: q.minRooms,
      maxRooms: q.maxRooms,
      transactionType: q.transactionType,
      // A typed "עד X" is a hard ceiling; a search without a stated budget
      // clears the flag so the deck's normal near-miss behaviour returns.
      strictMaxBudget: q.maxPrice != null,
      // NL amenities become preferred (soft) signals so a single missing tag
      // doesn't empty the deck for an older user typing casually.
      preferredFeatures: q.amenities.isEmpty
          ? null
          : {...base.preferredFeatures, ...q.amenities},
    );
  }

  void _clearNlSearch() {
    final provider = context.read<DatingProvider>();
    _nlController.clear();
    // Clearing also collapses the bar back to the icon so the card is full-size.
    setState(() {
      _nlSummary = null;
      _searchOpen = false;
    });
    // Reset the NL-driven criteria back to neutral, keeping the rest of the deck.
    unawaited(provider.updateFilters(provider.filters.copyWith(
      query: '',
      city: '',
      strictMaxBudget: false,
    )));
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkSavedSearches();
  }

  /// On app-foreground, fire local alerts for NEW listings matching the tenant's
  /// alerts-on saved searches. Fail-soft — never throws into the UI.
  Future<void> _checkSavedSearches() async {
    try {
      final provider = context.read<DatingProvider>();
      if (provider.isLandlord) return; // tenant feature only
      final searches = await SavedSearchRepository().loadAll();
      if (searches.isEmpty) return;
      await NotificationService.instance
          .checkSavedSearches(searches, provider.allProperties);
    } catch (_) {/* fail-soft */}
  }

  // ── View-side swipe signals (fail-soft, no UX impact) ─────────────────────
  // Dwell = time the top card was visible before the user acted on it.
  // Comparison set = the run of listings seen consecutively before a "decision"
  // (a like/super-like), capturing what the user weighed the chosen one against.
  DateTime _topCardShownAt = DateTime.now();
  final List<String> _comparisonIds = <String>[];

  // Stable deck the CardSwiper advances through — captured from
  // filteredProperties whenever the STRUCTURAL deckRevision changes (filter /
  // sort / catalog / pagination), NOT on every swipe. This is what lets the
  // swiper advance internally instead of being torn down + rebuilt per swipe.
  List<RentalProperty> _deck = const [];
  int _deckRev = -1;

  List<RentalProperty> _deckFor(DatingProvider p) {
    if (_deckRev != p.deckRevision) {
      _deck = List<RentalProperty>.of(p.filteredProperties);
      _deckRev = p.deckRevision;
      // A new deck surfaced → log impressions for the cards now visible at the
      // top (landmine #2). Fire-and-forget + deduped in the provider; safe here.
      p.logVisibleDeckImpressions(_deck, from: 0);
    }
    return _deck;
  }

  /// Wraps [DatingProvider.handlePropertySwipe] to emit dwell + comparison-set
  /// signals at the decision moment, then delegates unchanged.
  Future<bool> _onSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) async {
    RentalProperty? swiped;
    try {
      // The swiper advances the stable _deck snapshot, so previousIndex indexes
      // _deck (not the shrinking filteredProperties). Resolve the exact card.
      final props = _deck;
      if (previousIndex >= 0 && previousIndex < props.length) {
        final decided = props[previousIndex];
        swiped = decided;
        final dwellMs =
            DateTime.now().difference(_topCardShownAt).inMilliseconds;
        AppEvents.instance.service
            .logCardDwell(propertyId: decided.id, dwellMs: dwellMs);

        // Lead funnel: this listing was surfaced/seen in the deck (the `view`
        // step) — the entry point of the path toward leaving details. Mirror to
        // BehaviorInsights (funnel + exploration breadth).
        AppEvents.instance.service.logLeadFunnelStep(
          step: LeadFunnelStep.view,
          propertyId: decided.id,
        );
        BehaviorInsights.instance.noteFunnelStep(LeadFunnelStep.view);
        BehaviorInsights.instance.notePropertyViewed(
          propertyId: decided.id,
          area: decided.city,
          price: decided.price.toDouble(),
        );

        _comparisonIds.add(decided.id);
        final isLike = direction == CardSwiperDirection.right ||
            direction == CardSwiperDirection.top;
        if (isLike) {
          // A decision was reached: this run of listings was the comparison set.
          if (_comparisonIds.length > 1) {
            AppEvents.instance.service
                .logComparisonSet(propertyIds: List<String>.from(_comparisonIds));
          }
          _comparisonIds.clear();
        }
      }
      // The next card becomes visible now — restart the dwell clock.
      _topCardShownAt = DateTime.now();
    } catch (_) {/* fail-soft */}

    // The swipe advanced the deck — the card at [currentIndex] (and the back
    // cards behind it) just surfaced. Log their impressions (deduped in the
    // provider), so each newly-shown card becomes a real "shown" signal.
    final provider = context.read<DatingProvider>();
    if (currentIndex != null) {
      provider.logVisibleDeckImpressions(_deck, from: currentIndex);
    }

    // Delegate to the outcome handler, passing the EXACT swiped card (resolved
    // from the stable deck) so accounting never mis-indexes the shrinking list.
    return provider.handlePropertySwipe(
          previousIndex,
          currentIndex,
          direction,
          swiped: swiped,
          l10n: AppLocalizations.of(context)!,
        );
  }

  Widget _buildPillSelector() {
    return _PillSelector(
      selectedTab: _selectedTab,
      onTabChanged: (tab) {
        setState(() {
          _selectedTab = tab;
        });
      },
      onMapTap: () => _openAreaLasso(context, context.read<DatingProvider>()),
    );
  }


  Widget _buildDiscoverGrid(
    List<RentalProperty> properties,
    DatingProvider provider,
  ) {
    if (properties.isEmpty) {
      return _NoMorePropertiesState();
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 128, 16, 140),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.72,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: properties.length,
      itemBuilder: (context, index) {
        final p = properties[index];
        final media = p.primaryMedia;
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: 'PropertyDetailScreen'),
                builder: (_) => PropertyDetailScreen(
                    property: p, entrySource: 'deck', entryRank: index),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Full Card Image
                  _MatchPropertyImage(media: media),

                  // Bottom dark gradient overlay for text readability
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 120,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.85),
                              Colors.black.withOpacity(0.5),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Top horizontal glass pill badges (room count, size)
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _GlassPillBadge(
                          icon: IconsaxPlusLinear.building,
                          label: AppLocalizations.of(context)!
                              .discoverScreenC6efa96a(p.roomsLabel),
                        ),
                        _GlassPillBadge(
                          icon: IconsaxPlusLinear.maximize_3,
                          label: AppLocalizations.of(context)!
                              .discoverScreen615d28b8(p.sizeM2),
                        ),
                      ],
                    ),
                  ),

                  // Bottom Text: Price & Address
                  Positioned(
                    bottom: 12,
                    left: 12,
                    right: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Real engagement badges from the listing's own market
                        // signals — each hidden at 0, so no fabricated numbers.
                        ..._realSignalBadges(context, p),
                        Text(
                          p.priceLabel,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const RentlyIcon(
                              IconsaxPlusLinear.location,
                              size: 11,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                p.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white70,
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
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final properties = provider.filteredProperties;
        // Stable deck the swiper advances (rebuilt only on structural changes).
        final deck = _deckFor(provider);

        // Tapping the navbar search tab bumps this signal → snap back to the
        // swipe deck from whatever view (grid/map) the user left it on.
        final swipesSignal = provider.discoverSwipesSignal;
        if (swipesSignal != _lastSwipesSignal) {
          _lastSwipesSignal = swipesSignal;
          if (_selectedTab != DiscoverTab.forYou) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedTab = DiscoverTab.forYou);
            });
          }
        }

        return Scaffold(
          appBar: null,
          body: Stack(
            children: [
              Positioned.fill(
                child: provider.isLoading
                    ? const _SkeletonDiscoverView()
                    : _selectedTab == DiscoverTab.discover
                        ? SafeArea(
                            bottom: false,
                            child: _buildDiscoverGrid(properties, provider),
                          )
                        : SafeArea(
                            bottom: false,
                            child: Stack(
                              children: [
                                // Full-height card swiper extending almost to the bottom navbar
                                Positioned.fill(
                                  child: properties.isNotEmpty
                                      ? CardSwiper(
                                          // Key on the STRUCTURAL deck revision,
                                          // not per-swipe — so a swipe advances
                                          // the swiper instead of rebuilding it.
                                          key: ValueKey(provider.deckRevision),
                                          controller:
                                              provider.propertySwiperController,
                                          cardsCount: deck.length,
                                          // Card returns to its full long size —
                                          // only the floating header sits above it
                                          // now (the search bar is an overlay).
                                          padding: const EdgeInsets.fromLTRB(
                                            10,
                                            72,
                                            10,
                                            130,
                                          ),
                                          scale: 0.93,
                                          threshold: 38,
                                          maxAngle: 16,
                                          isLoop: false,
                                          numberOfCardsDisplayed:
                                              math.min(3, deck.length),
                                          backCardOffset: const Offset(0, 20),
                                          allowedSwipeDirection:
                                              const AllowedSwipeDirection.only(
                                            left: true,
                                            right: true,
                                            up: true,
                                          ),
                                          onSwipe: _onSwipe,
                                          cardBuilder: (
                                            context,
                                            index,
                                            horizontalOffsetPercentage,
                                            verticalOffsetPercentage,
                                          ) {
                                            if (index < 0 ||
                                                index >= deck.length) {
                                              return const SizedBox.shrink();
                                            }
                                            return Stack(
                                              children: [
                                                ProfileCard(
                                                  key: ValueKey(
                                                    deck[index].id,
                                                  ),
                                                  property: deck[index],
                                                  horizontalOffsetPercentage:
                                                      horizontalOffsetPercentage,
                                                ),
                                                // Isolate the FOMO overlay's
                                                // always-on animations (live-
                                                // viewers pulse, hot badge) so
                                                // their continuous repaints don't
                                                // invalidate the whole card/deck.
                                                RepaintBoundary(
                                                  child: FomoCardOverlay(
                                                    property: deck[index],
                                                    likedIds:
                                                        provider.likedPropertyIds,
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        )
                                      : _NoMorePropertiesState(),
                                ),

                                // Floating centered action buttons row — only
                                // while there are cards; otherwise it would sit
                                // on top of the empty-state and swallow taps on
                                // its quick-action buttons.
                                if (properties.isNotEmpty)
                                  Positioned(
                                    bottom: 140,
                                    left: 0,
                                    right: 0,
                                    // Isolate the buttons' pulse animation from
                                    // the deck's repaints.
                                    child: RepaintBoundary(
                                      child: ActionButtons(
                                        onSwipeLeft: provider.swipePropertyLeft,
                                        onSwipeRight: provider.swipePropertyRight,
                                        onVirtualTour: () {
                                          if (properties.isEmpty) return;
                                          openPropertyTour(
                                              context, properties.first);
                                        },
                                      ),
                                    ),
                                  ),

                                // Floating Undo button independently positioned on the bottom-left corner
                                if (properties.isNotEmpty && provider.canUndo)
                                  Positioned(
                                    bottom: 133,
                                    left: 24,
                                    child: Tooltip(
                                      message: AppLocalizations.of(context)!
                                          .discoverScreenF1872f35,
                                      child: GestureDetector(
                                        onTap: () {
                                          HapticFeedback.lightImpact();
                                          provider.undoSwipe();
                                        },
                                        child: Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: AppColors.slate200,
                                              width: 1.5,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.amber
                                                    .withOpacity(0.12),
                                                blurRadius: 12,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.rotate_left_rounded,
                                            color: AppColors.amber,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
              ),
              // Floating header containing selector and filters button
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                left: 12,
                right: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (!provider.isLandlord)
                      const _HeaderMenuButton()
                    else
                      const SizedBox(width: 42),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: _buildPillSelector(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildFiltersButton(context, provider),
                  ],
                ),
              ),
              // Natural-language search — a fully-rounded pill on the right that
              // animates open/closed over ~1s (the circle elongates into the full
              // bar). Collapsed by default so the swipe card keeps its full size.
              if (!provider.isLandlord)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 58,
                  left: 16,
                  right: 16,
                  child: _AnimatedNlSearch(
                    open: _searchOpen,
                    controller: _nlController,
                    busy: _nlBusy,
                    summary: _nlSummary,
                    onOpen: () => setState(() => _searchOpen = true),
                    onClose: () => setState(() => _searchOpen = false),
                    onSubmit: _runNlSearch,
                    onClear: _clearNlSearch,
                    // "מומלץ בשבילך" — resolve the CF-recommended ids to live
                    // listings for the strip under the field. Empty ⇒ hidden.
                    recommended: provider.cfRecommendedIds
                        .map(provider.propertyById)
                        .whereType<RentalProperty>()
                        .toList(),
                    onRecommendedTap: (p) {
                      setState(() => _searchOpen = false);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              PropertyDetailScreen(property: p, entrySource: 'cf'),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // Map + lasso access, moved out of the filter sheet into a dedicated round
  // button that sits next to the "גלה" selector.
  Future<void> _openAreaLasso(
      BuildContext context, DatingProvider provider) async {
    // The map/lasso overview is the one view that wants the WHOLE catalogue, so
    // pull the remaining pages now (on demand) rather than eager-loading 1500
    // properties at app startup. Fire-and-forget — the map fills in as it lands.
    unawaited(provider.ensureFullCatalogLoaded());
    final f = provider.filters;
    final area = f.hasCustomArea
        ? SearchArea.custom(polygon: f.customAreaPolygon)
        : provider.searchAreas.firstWhere(
            (item) => item.id == f.areaId,
            orElse: () => provider.selectedArea,
          );
    final polygon = await Navigator.of(context).push<List<LatLng>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AreaLassoScreen(
          initialArea: area,
          initialPolygon: f.customAreaPolygon,
          previewMarkers: provider.previewFilteredProperties(f, limit: 70),
          filters: f,
        ),
      ),
    );
    if (!mounted || polygon == null) return;
    await provider.updateFilters(f.copyWith(
      city: '',
      areaId: 'all_israel',
      customAreaPolygon: polygon,
    ));
  }

  Widget _buildFiltersButton(BuildContext context, DatingProvider provider) {
    return GestureDetector(
      onTap: provider.isLoading
          ? null
          : () => _showFilters(context, provider),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: PlatformFx.blurSigma(10),
                sigmaY: PlatformFx.blurSigma(10),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.87), // 13% transparent (87% opaque)
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.slate200.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: RentlyIcon(
                    IconsaxPlusLinear.setting_4,
                    size: 20,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ),
          ),
          if (provider.activeFilterCount > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${provider.activeFilterCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showFilters(
    BuildContext context,
    DatingProvider provider,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FiltersSheet(provider: provider),
    );
  }
}

class MatchCelebrationOverlay extends StatefulWidget {
  MatchCelebrationOverlay({super.key, required this.property});
  final RentalProperty property;

  @override
  State<MatchCelebrationOverlay> createState() =>
      _MatchCelebrationOverlayState();
}

class _MatchCelebrationOverlayState extends State<MatchCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  late final Animation<double> _heartScale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    _scale = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
    );
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    );
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.22), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.22, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.12), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 20),
    ]).animate(CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
    ));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.property;
    final propertyMedia = p.primaryMedia;
    final provider = context.watch<DatingProvider>();
    final tenantProfile = provider.tenantProfile;

    // Tenant Avatar / Photo
    final String? tenantPhoto = (tenantProfile?.photoUrls.isNotEmpty == true)
        ? tenantProfile!.photoUrls.first
        : null;

    final String tenantName = tenantProfile?.name ??
        AppLocalizations.of(context)!.discoverScreenC4b9553a;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 1. Dark Blur Background
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: PlatformFx.blurSigma(22),
                sigmaY: PlatformFx.blurSigma(22),
              ),
              child: Container(
                color: const Color(0xFF090D16).withOpacity(0.85),
              ),
            ),
          ),

          // 2. Ambient Purple & Blue Glow
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.85,
                  colors: [
                    const Color(0xFF7C3AED).withOpacity(0.28),
                    const Color(0xFF3B82F6).withOpacity(0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: FadeTransition(
              opacity: _fade,
              child: Column(
                children: [
                  // Top Row: Close 'X' Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 10),

                          // Header: "IT'S A MATCH!"
                          ScaleTransition(
                            scale: _scale,
                            child: const Text(
                              "IT'S A MATCH!",
                              style: TextStyle(
                                fontSize: 38,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 2.2,
                                height: 1.1,
                                shadows: [
                                  Shadow(
                                    color: Colors.black45,
                                    offset: Offset(0, 4),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 28),

                          // Dual Overlapping Polaroid Cards + Dashed Arc + Floating Heart Badge
                          ScaleTransition(
                            scale: _scale,
                            child: SizedBox(
                              height: 270,
                              width: double.infinity,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Dashed Curved Path
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _DashedArcPainter(),
                                    ),
                                  ),

                                  // Left Polaroid Card (Tenant Profile)
                                  Positioned(
                                    left: MediaQuery.of(context).size.width * 0.12,
                                    child: Transform.rotate(
                                      angle: -0.13, // ~ -7.5 degrees
                                      child: _MatchPolaroidCard(
                                        photoUrl: tenantPhoto,
                                        title: tenantName,
                                        fallbackIcon: Icons.person_rounded,
                                      ),
                                    ),
                                  ),

                                  // Right Polaroid Card (Apartment Property)
                                  Positioned(
                                    right: MediaQuery.of(context).size.width * 0.12,
                                    child: Transform.rotate(
                                      angle: 0.13, // ~ +7.5 degrees
                                      child: _MatchPolaroidCard(
                                        media: propertyMedia,
                                        title: p.address.isNotEmpty
                                            ? p.address
                                            : AppLocalizations.of(context)!
                                                .discoverScreen8a84741d,
                                        fallbackIcon: Icons.apartment_rounded,
                                      ),
                                    ),
                                  ),

                                  // Center Floating Glowing Heart Circle Badge
                                  ScaleTransition(
                                    scale: _heartScale,
                                    child: Container(
                                      width: 72,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF8B5CF6),
                                            Color(0xFF6366F1),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 3.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF8B5CF6).withOpacity(0.55),
                                            blurRadius: 24,
                                            spreadRadius: 3,
                                          ),
                                        ],
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.favorite_rounded,
                                          color: Colors.white,
                                          size: 34,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Subtitle Copy tailored to Rently
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              children: [
                                Text(
                                  AppLocalizations.of(context)!
                                      .discoverScreen4b403e4b,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  AppLocalizations.of(context)!
                                      .discoverScreen1b24cc81(p.address),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    color: Color(0xFF94A3B8),
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 36),

                          // Action Buttons
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              children: [
                                // Write Message / Open Chat Pill Button
                                SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(30),
                                      onTap: () => Navigator.of(context).pop(),
                                      child: Ink(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(30),
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF8B5CF6),
                                              Color(0xFF6366F1),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF8B5CF6).withOpacity(0.4),
                                              blurRadius: 20,
                                              offset: const Offset(0, 5),
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                IconsaxPlusBold.message,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                AppLocalizations.of(context)!
                                                    .discoverScreenB2320205,
                                                style: const TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w900,
                                                  color: Colors.white,
                                                  letterSpacing: -0.2,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                // Keep Browsing Button
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: Text(
                                    AppLocalizations.of(context)!
                                        .discoverScreen4fb78a2e,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
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

class _MatchPolaroidCard extends StatelessWidget {
  const _MatchPolaroidCard({
    this.photoUrl,
    this.media,
    required this.title,
    required this.fallbackIcon,
  });

  final String? photoUrl;
  final PropertyMedia? media;
  final String title;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 155,
      height: 215,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _buildImage(),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return Image.network(
        photoUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    if (media != null) {
      return SafeMedia(
        media: media!,
        fallback: _fallback(),
        fit: BoxFit.cover,
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
        color: const Color(0xFF0F172A),
        child: Center(
          child: Icon(
            fallbackIcon,
            color: Colors.white54,
            size: 36,
          ),
        ),
      );
}

class _DashedArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.45)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    // Arc curving over left card towards bottom right
    path.moveTo(size.width * 0.12, size.height * 0.28);
    path.cubicTo(
      size.width * 0.25, size.height * 0.05,
      size.width * 0.65, size.height * 0.08,
      size.width * 0.85, size.height * 0.35,
    );
    path.cubicTo(
      size.width * 0.95, size.height * 0.55,
      size.width * 0.88, size.height * 0.82,
      size.width * 0.78, size.height * 0.88,
    );

    // Draw dashed path
    const dashWidth = 6.0;
    const dashSpace = 5.0;
    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double len = (distance + dashWidth < metric.length)
            ? dashWidth
            : metric.length - distance;
        canvas.drawPath(metric.extractPath(distance, distance + len), paint);
        distance += dashWidth + dashSpace;
      }
    }

    // Draw Arrow Head at the end of the arc
    final metrics = path.computeMetrics().toList();
    if (metrics.isNotEmpty) {
      final endMetric = metrics.last;
      final tangent = endMetric.getTangentForOffset(endMetric.length * 0.98);
      if (tangent != null) {
        final arrowPaint = Paint()
          ..color = Colors.white.withOpacity(0.65)
          ..style = PaintingStyle.fill;
        final arrowPath = Path();
        final tip = tangent.position;
        final angle = tangent.angle;
        arrowPath.moveTo(tip.dx, tip.dy);
        arrowPath.lineTo(
          tip.dx - 10 * math.cos(angle - 0.45),
          tip.dy - 10 * math.sin(angle - 0.45),
        );
        arrowPath.lineTo(
          tip.dx - 10 * math.cos(angle + 0.45),
          tip.dy - 10 * math.sin(angle + 0.45),
        );
        arrowPath.close();
        canvas.drawPath(arrowPath, arrowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MatchPropertyImage extends StatelessWidget {
  const _MatchPropertyImage({required this.media});

  final PropertyMedia? media;

  @override
  Widget build(BuildContext context) {
    final m = media;
    if (m == null) {
      return _fallback();
    }
    return SafeMedia(
      media: m,
      fallback: _fallback(),
      fit: BoxFit.cover,
    );
  }

  Widget _fallback() => Container(
        color: AppColors.navy,
        child: const Center(
          child: RentlyIcon(
            IconsaxPlusLinear.building,
            color: Colors.white30,
            size: 40,
          ),
        ),
      );
}

// Real engagement badges for a grid card, built from the listing's own market
// signals. Each badge appears only when its value is > 0, and "חדש!" only when
// the listing was created in the last 7 days — no fabricated numbers.
List<Widget> _realSignalBadges(BuildContext context, RentalProperty p) {
  final s = p.marketSignals;
  final isNew = p.createdAt != null &&
      DateTime.now().difference(p.createdAt!).inDays < 7;
  final badges = <Widget>[
    if (isNew)
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.red.withOpacity(0.25),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.red.withOpacity(0.4), width: 0.8),
        ),
        child: Text(AppLocalizations.of(context)!.discoverScreen8542ba18,
            style: const TextStyle(
                color: AppColors.dangerSoft,
                fontWeight: FontWeight.w900,
                fontSize: 9)),
      ),
    if (s.views > 0)
      _GlassPillBadge(icon: IconsaxPlusLinear.eye, label: '${s.views}'),
    if (s.likes > 0)
      _GlassPillBadge(icon: IconsaxPlusLinear.heart, label: '${s.likes}'),
    if (s.liveViewers > 0)
      _GlassPillBadge(
          icon: IconsaxPlusLinear.people, label: '${s.liveViewers}'),
  ];
  if (badges.isEmpty) return const [];
  return [
    Row(
      children: [
        for (var i = 0; i < badges.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          badges[i],
        ],
      ],
    ),
    const SizedBox(height: 6),
  ];
}

class _GlassPillBadge extends StatelessWidget {
  const _GlassPillBadge({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    // A solid frosted-look pill — NO BackdropFilter blur. Real-time blur here ran
    // twice per grid cell (~16 live gaussian blurs while scrolling), the main
    // cause of the browse-grid jank/freezes. A darker translucent fill reads the
    // same over photos at a fraction of the GPU cost.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Natural-language search that lives on the right of the discover header as a
/// fully-rounded pill. Collapsed it's a 52px circle with a search icon; tapping
/// it animates (~1s) into the full-width search bar — the circle elongates and
/// widens leftward until it reaches full size. Closing reverses the same way.
class _AnimatedNlSearch extends StatefulWidget {
  _AnimatedNlSearch({
    required this.open,
    required this.controller,
    required this.busy,
    required this.summary,
    required this.onOpen,
    required this.onClose,
    required this.onSubmit,
    required this.onClear,
    required this.recommended,
    required this.onRecommendedTap,
  });

  final bool open;
  final TextEditingController controller;
  final bool busy;
  final String? summary;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;
  // CF-recommended listings for the "מומלץ בשבילך" strip revealed under the
  // expanded field, and the tap handler that opens one.
  final List<RentalProperty> recommended;
  final ValueChanged<RentalProperty> onRecommendedTap;

  @override
  State<_AnimatedNlSearch> createState() => _AnimatedNlSearchState();
}

class _AnimatedNlSearchState extends State<_AnimatedNlSearch>
    with SingleTickerProviderStateMixin {
  static const double _h = 52; // pill height == collapsed circle diameter
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  late final Animation<double> _t =
      CurvedAnimation(parent: _anim, curve: Curves.easeInOutCubic);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.open) _anim.value = 1;
    // Focus the field only once fully expanded, so the keyboard doesn't race
    // the animation.
    _anim.addStatusListener((s) {
      if (s == AnimationStatus.completed && widget.open) _focus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(_AnimatedNlSearch old) {
    super.didUpdateWidget(old);
    if (widget.open && !old.open) {
      _anim.forward();
    } else if (!widget.open && old.open) {
      _focus.unfocus();
      _anim.reverse();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width - 32; // left16 + right16
    return Align(
      alignment: Alignment.centerRight,
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final t = _t.value;
          final w = _h + (maxW - _h) * t;
          final contentOpacity = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
          final iconOpacity = (1 - t / 0.5).clamp(0.0, 1.0);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: widget.open ? null : widget.onOpen,
                child: Container(
                  width: w,
                  // Fixed height — the collapse animation morphs a 52px circle (with
                  // the search icon) into the bar; the icon overlay is Positioned.fill
                  // so this MUST stay a definite height or the icon disappears.
                  height: _h,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(_h / 2), // fully rounded
                    border: Border.all(color: AppColors.primary, width: 1.6),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.16),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      if (iconOpacity > 0)
                        Positioned.fill(
                          child: Opacity(
                            opacity: iconOpacity,
                            child: Center(
                              child: RentlyIcon(
                                IconsaxPlusLinear.search_normal,
                                size: 22,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      if (contentOpacity > 0)
                        Positioned.fill(
                          child: Opacity(
                            opacity: contentOpacity,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(_h / 2),
                              child: OverflowBox(
                                minWidth: maxW,
                                maxWidth: maxW,
                                alignment: Alignment.centerRight,
                                child: _row(),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (t > 0.92)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8, left: 8),
                  child: _belowText(),
                ),
              // "מומלץ בשבילך" — CF picks, shown once the bar is fully open and
              // the field is still empty (no active search yet). Rebuilds on
              // typing via the controller so it hides the moment the user types.
              if (t > 0.92 && widget.summary == null)
                Padding(
                  padding: const EdgeInsets.only(right: 8, left: 8),
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.controller,
                    builder: (context, value, _) {
                      if (value.text.isNotEmpty) return const SizedBox.shrink();
                      return RecommendedForYouStrip(
                        properties: widget.recommended,
                        onTap: widget.onRecommendedTap,
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _row() {
    final busy = widget.busy;
    final hasContent =
        widget.controller.text.isNotEmpty || widget.summary != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          const SizedBox(width: 10),
          if (busy)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: AppColors.primary,
              ),
            )
          else
            RentlyIcon(IconsaxPlusLinear.search_normal,
                size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              enabled: !busy,
              textInputAction: TextInputAction.search,
              onSubmitted: widget.onSubmit,
              maxLines: 1,
              // Vertically centre the text within the pill (it used to sit high).
              textAlignVertical: TextAlignVertical.center,
              cursorColor: AppColors.primary,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.navy,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                isDense: true,
                // The global InputDecorationTheme fills fields with a light-gray
                // (0xFFF1F5F8) — override to keep the pill fully white.
                filled: true,
                fillColor: Colors.white,
                hintText:
                    AppLocalizations.of(context)!.discoverScreen59e95c52,
                hintStyle: TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          IconButton(
            tooltip: hasContent
                ? AppLocalizations.of(context)!.discoverScreenE8b3a3d5
                : AppLocalizations.of(context)!.discoverScreen55247199,
            icon: const RentlyIcon(IconsaxPlusLinear.close_circle,
                size: 18, color: AppColors.textSecondary),
            onPressed:
                busy ? null : (hasContent ? widget.onClear : widget.onClose),
          ),
          GestureDetector(
            onTap: busy ? null : () => widget.onSubmit(widget.controller.text),
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _belowText() {
    if (widget.summary == null) {
      return Text(
        AppLocalizations.of(context)!.discoverScreen31d3427c,
        style: TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary.withValues(alpha: 0.9),
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryLight2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          RentlyIcon(IconsaxPlusLinear.search_status,
              size: 14, color: AppColors.primaryDark),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.summary!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The 3-dot "more" header button (top-right). Holds notifications, saved
/// searches and saved apartments in one menu, and shows a small unread dot when
/// notifications are waiting — this is where the tenant reaches notifications.
class _HeaderMenuButton extends StatefulWidget {
  const _HeaderMenuButton();

  @override
  State<_HeaderMenuButton> createState() => _HeaderMenuButtonState();
}

class _HeaderMenuButtonState extends State<_HeaderMenuButton>
    with WidgetsBindingObserver {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final res = await AwsApiClient.instance.getNotifications();
      if (!mounted) return;
      if (res.unread != _unread) setState(() => _unread = res.unread);
    } catch (_) {}
  }

  void _onSelected(int v) {
    if (v == 0) {
      Navigator.of(context)
          .push<AppNotification>(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()))
          .then((tapped) {
        _refresh();
        if (tapped != null && mounted) _routeNotification(tapped);
      });
      return;
    }
    final Widget page =
        v == 1 ? const SavedSearchesScreen() : const SavedPropertiesScreen();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  /// Routes a tapped notification (tenant context: Matches is tab 1).
  void _routeNotification(AppNotification n) {
    final provider = context.read<DatingProvider>();
    switch (n.type) {
      case 'match':
      case 'message':
        provider.setTabIndex(1);
        provider.markMatchesSeen();
      case 'like':
      case 'property_like':
      case 'tour':
      case 'tour_ready':
      case 'review':
      case 'saved_search':
        final property = provider.propertyById(n.propertyId);
        if (property != null) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PropertyDetailScreen(property: property),
          ));
        }
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: 42,
          width: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.slate200, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: PopupMenuButton<int>(
            tooltip: AppLocalizations.of(context)!.discoverScreenB429a0f3,
            padding: EdgeInsets.zero,
            position: PopupMenuPosition.under,
            icon: const Icon(Icons.more_vert, size: 20, color: AppColors.navy),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            onSelected: _onSelected,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 0,
                child: _HeaderMenuRow(
                    icon: IconsaxPlusLinear.notification,
                    label: AppLocalizations.of(context)!.discoverScreenA8e71c4c,
                    badge: _unread),
              ),
              PopupMenuItem(
                value: 1,
                child: _HeaderMenuRow(
                    icon: Icons.bookmark_border_rounded,
                    label:
                        AppLocalizations.of(context)!.discoverScreen86023c2b),
              ),
              PopupMenuItem(
                value: 2,
                child: _HeaderMenuRow(
                    icon: Icons.favorite_border_rounded,
                    label:
                        AppLocalizations.of(context)!.discoverScreen2f416fd3),
              ),
            ],
          ),
        ),
        if (_unread > 0)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: const BoxDecoration(
                color: AppColors.coral,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _unread > 9 ? '9+' : '$_unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HeaderMenuRow extends StatelessWidget {
  _HeaderMenuRow(
      {required this.icon, required this.label, this.badge = 0});
  final IconData icon;
  final String label;
  final int badge;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          if (badge > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badge > 9 ? '9+' : '$badge',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SaveSearchButton extends StatelessWidget {
  _SaveSearchButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: AppLocalizations.of(context)!.discoverScreen8f28a31a,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RentlyIcon(IconsaxPlusLinear.save_2,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  AppLocalizations.of(context)!.discoverScreenF50251bc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
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

// ─── Filters Sheet ────────────────────────────────────────────────────────────

class _FiltersSheet extends StatefulWidget {
  _FiltersSheet({required this.provider});
  final DatingProvider provider;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  static const Duration _doubleTapWindow = Duration(milliseconds: 260);
  late final TextEditingController _locationCtrl;
  late final TextEditingController _minRoomsCtrl;
  late final TextEditingController _maxRoomsCtrl;
  Timer? _pendingPriorityTimer;
  String? _pendingPriorityKey;
  late SearchFilters _draftFilters;
  late final String _initialFiltersKey;
  late int _visibleCount;
  late List<RentalProperty> _markerPreview;
  bool _didCommit = false;
  bool _showAllFeatures = false;

  @override
  void initState() {
    super.initState();
    _draftFilters = widget.provider.filters;
    _initialFiltersKey = _filtersKey(_draftFilters);
    _visibleCount = widget.provider.filteredCountFor(_draftFilters);
    _markerPreview = widget.provider.previewFilteredProperties(_draftFilters);
    _locationCtrl = TextEditingController(text: widget.provider.filters.city);
    _minRoomsCtrl = TextEditingController(
      text: _draftFilters.minRooms == 0
          ? ''
          : (_draftFilters.minRooms % 1 == 0
              ? _draftFilters.minRooms.toInt().toString()
              : _draftFilters.minRooms.toString()),
    );
    _maxRoomsCtrl = TextEditingController(
      text: _draftFilters.maxRooms >= 10
          ? ''
          : (_draftFilters.maxRooms % 1 == 0
              ? _draftFilters.maxRooms.toInt().toString()
              : _draftFilters.maxRooms.toString()),
    );
    widget.provider.addListener(_refreshMarkers);
  }

  void _refreshMarkers() {
    if (mounted) {
      setState(() {
        _markerPreview =
            widget.provider.previewFilteredProperties(_draftFilters);
      });
    }
  }

  @override
  void dispose() {
    widget.provider.removeListener(_refreshMarkers);
    _commitDraftIfNeeded();
    _pendingPriorityTimer?.cancel();
    _locationCtrl.dispose();
    _minRoomsCtrl.dispose();
    _maxRoomsCtrl.dispose();
    super.dispose();
  }

  void _setDraftFilters(SearchFilters filters, DatingProvider provider) {
    final count = provider.filteredCountFor(filters);
    final markers = provider.previewFilteredProperties(filters);
    _emitFilterChanges(_draftFilters, filters);
    setState(() {
      _draftFilters = filters;
      _visibleCount = count;
      _markerPreview = markers;
    });
  }

  /// View-side signal: emit one [logFilterChange] per field that actually
  /// changed value between the previous and next draft. Fail-soft, no UX.
  void _emitFilterChanges(SearchFilters oldF, SearchFilters newF) {
    try {
      final svc = AppEvents.instance.service;
      void diff(String field, Object? oldV, Object? newV) {
        if (oldV != newV) {
          svc.logFilterChange(field: field, oldValue: oldV, newValue: newV);
        }
      }

      diff('transactionType', oldF.transactionType.name,
          newF.transactionType.name);
      diff('minBudget', oldF.minBudget, newF.minBudget);
      diff('maxBudget', oldF.maxBudget, newF.maxBudget);
      diff('minRooms', oldF.minRooms, newF.minRooms);
      diff('maxRooms', oldF.maxRooms, newF.maxRooms);
      diff('city', oldF.city, newF.city);
      diff('areaId', oldF.areaId, newF.areaId);
      diff('minSizeM2', oldF.minSizeM2, newF.minSizeM2);
      diff('maxSizeM2', oldF.maxSizeM2, newF.maxSizeM2);
      diff('minFloor', oldF.minFloor, newF.minFloor);
      diff('moveInFilter', oldF.moveInFilter.name, newF.moveInFilter.name);
      diff('listingSource', oldF.listingSource.name, newF.listingSource.name);
      diff('sortBy', oldF.sortBy.name, newF.sortBy.name);
      diff('includeUnknownPriceListings', oldF.includeUnknownPriceListings,
          newF.includeUnknownPriceListings);
      diff('requiredFeatures', oldF.requiredFeatures.length,
          newF.requiredFeatures.length);
      diff('preferredFeatures', oldF.preferredFeatures.length,
          newF.preferredFeatures.length);
      diff('propertyTypes', oldF.propertyTypes.length,
          newF.propertyTypes.length);
      diff('conditions', oldF.conditions.length, newF.conditions.length);
    } catch (_) {/* fail-soft */}
  }

  SearchFilters _filtersForTransaction(
    SearchFilters filters,
    TransactionTypeFilter type,
  ) {
    final sliderMin = _priceSliderMin(type).round();
    final sliderMax = _priceSliderMax(type).round();
    return filters.copyWith(
      transactionType: type,
      minBudget: sliderMin,
      maxBudget: sliderMax,
    );
  }

  String _transactionMetric(
    DatingProvider provider,
    SearchFilters filters,
    TransactionTypeFilter type,
  ) {
    final scopedFilters = _filtersForTransaction(filters, type);
    final count = provider.filteredCountFor(scopedFilters);
    final averagePrice = provider.averagePriceFor(scopedFilters);
    final price = averagePrice <= 0
        ? AppLocalizations.of(context)!.discoverScreenA43e6e7d
        : _compactPriceLabel(averagePrice.round());
    return AppLocalizations.of(context)!.discoverScreen74b0b436(count, price);
  }

  String _filtersKey(SearchFilters filters) {
    return jsonEncode({
      ...filters.toJson(),
      'requiredFeatures': filters.requiredFeatures.toList()..sort(),
      'preferredFeatures': filters.preferredFeatures.toList()..sort(),
      'propertyTypes': filters.propertyTypes.toList()..sort(),
      'preferredPropertyTypes': filters.preferredPropertyTypes.toList()..sort(),
      'conditions': filters.conditions.toList()..sort(),
      'preferredConditions': filters.preferredConditions.toList()..sort(),
      'requiredListingSources':
          filters.requiredListingSources.map((source) => source.name).toList()
            ..sort(),
      'preferredListingSources':
          filters.preferredListingSources.map((source) => source.name).toList()
            ..sort(),
      'requiredMoveInFilters':
          filters.requiredMoveInFilters.map((filter) => filter.name).toList()
            ..sort(),
      'preferredMoveInFilters':
          filters.preferredMoveInFilters.map((filter) => filter.name).toList()
            ..sort(),
    });
  }

  bool get _hasPendingChanges =>
      _filtersKey(_draftFilters) != _initialFiltersKey;

  void _commitDraftIfNeeded() {
    if (_didCommit || !_hasPendingChanges) return;
    _didCommit = true;
    unawaited(widget.provider.updateFilters(_draftFilters));
  }

  /// One tap marks preferred, a second quick tap upgrades to required.
  /// Tapping an already-selected chip clears it.
  void _handlePriorityTap({
    required String key,
    required FilterPriority current,
    required ValueChanged<FilterPriority> onSelected,
  }) {
    if (current == FilterPriority.required ||
        (current == FilterPriority.preferred && _pendingPriorityKey != key)) {
      _pendingPriorityTimer?.cancel();
      _pendingPriorityKey = null;
      onSelected(FilterPriority.none);
      return;
    }

    if (_pendingPriorityKey == key) {
      _pendingPriorityTimer?.cancel();
      _pendingPriorityKey = null;
      onSelected(FilterPriority.required);
      return;
    }

    _pendingPriorityTimer?.cancel();
    _pendingPriorityKey = key;
    onSelected(FilterPriority.preferred);
    _pendingPriorityTimer = Timer(_doubleTapWindow, () {
      if (_pendingPriorityKey == key) {
        _pendingPriorityKey = null;
      }
    });
  }

  Future<void> _editSliderValue({
    required BuildContext context,
    required String title,
    required String initialValue,
    required String suffix,
    required TextInputType keyboardType,
    required ValueChanged<String> onSubmitted,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            title,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: TextField(
            controller: controller,
            keyboardType: keyboardType,
            autofocus: true,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              suffixText: suffix.isEmpty ? null : suffix,
              hintText: AppLocalizations.of(context)!.discoverScreen6c3c338f,
            ),
            onSubmitted: (submitted) =>
                Navigator.of(dialogContext).pop(submitted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child:
                  Text(AppLocalizations.of(context)!.discoverScreenA7c55a8d),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child:
                  Text(AppLocalizations.of(context)!.discoverScreenF50251bc),
            ),
          ],
        );
      },
    );

    if (value == null) return;
    onSubmitted(value);
  }

  Future<void> _editRangeValues({
    required BuildContext context,
    required String title,
    required String initialMinValue,
    required String initialMaxValue,
    required String suffix,
    required TextInputType keyboardType,
    required void Function(String minValue, String maxValue) onSubmitted,
  }) async {
    final minController = TextEditingController(text: initialMinValue);
    final maxController = TextEditingController(text: initialMaxValue);
    final values = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) {
        InputDecoration decoration(String hint) => InputDecoration(
              suffixText: suffix.isEmpty ? null : suffix,
              hintText: hint,
            );

        return AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            title,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: minController,
                keyboardType: keyboardType,
                autofocus: true,
                textAlign: TextAlign.right,
                decoration: decoration(
                    AppLocalizations.of(context)!.discoverScreen7a683618),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maxController,
                keyboardType: keyboardType,
                textAlign: TextAlign.right,
                decoration: decoration(
                    AppLocalizations.of(context)!.discoverScreen6dd38cc5),
                onSubmitted: (_) => Navigator.of(dialogContext).pop(
                  (minController.text, maxController.text),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child:
                  Text(AppLocalizations.of(context)!.discoverScreenA7c55a8d),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                (minController.text, maxController.text),
              ),
              child:
                  Text(AppLocalizations.of(context)!.discoverScreenF50251bc),
            ),
          ],
        );
      },
    );

    if (values == null) return;
    onSubmitted(values.$1, values.$2);
  }

  /// Persist the current draft filters as a named saved search (with alerts on).
  /// Prompts for a name, then calls the saved-search feature's public API.
  Future<void> _saveCurrentSearch(BuildContext context) async {
    final f = _draftFilters;
    final l10n = AppLocalizations.of(context)!;
    final nameCtrl = TextEditingController(
      text: f.city.trim().isNotEmpty
          ? l10n.discoverScreenCe114a5b(f.city.trim())
          : l10n.discoverScreenC7d46456,
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => Directionality(
        textDirection: Directionality.of(context),
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            l10n.discoverScreenEd1b4e42,
            style: const TextStyle(
                color: AppColors.navy, fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.discoverScreenE9b8eecc,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textAlign: TextAlign.right,
                decoration:
                    InputDecoration(hintText: l10n.discoverScreen448f2c74),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(l10n.discoverScreenA7c55a8d),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(nameCtrl.text),
              child: Text(l10n.discoverScreenF50251bc),
            ),
          ],
        ),
      ),
    );
    if (name == null) return;

    final transactionType = switch (f.transactionType) {
      TransactionTypeFilter.rent => 'rent',
      TransactionTypeFilter.sale => 'sale',
      TransactionTypeFilter.any => null,
    };
    await SavedSearchesScreen.saveCurrent(
      context: context,
      name: name,
      city: f.city.trim().isEmpty ? null : f.city.trim(),
      minBudget: f.minBudget > 600 ? f.minBudget : null,
      maxBudget: f.maxBudget < 2000000000 ? f.maxBudget : null,
      minRooms: f.minRooms > 0 ? f.minRooms : null,
      maxRooms: f.maxRooms < 10 ? f.maxRooms : null,
      transactionType: transactionType,
      requiredTags: f.requiredFeatures.toList(),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2500),
      content: Text(AppLocalizations.of(context)!.discoverScreen58220e78),
    ));
  }

  void _resetFilters(DatingProvider provider) {
    const resetFilters = SearchFilters(
      query: '',
      minBudget: 600,
      maxBudget: 40000,
      minRooms: 0,
      maxRooms: 10,
      areaId: 'all_israel',
      requiredFeatures: <String>{},
      preferredFeatures: <String>{},
      minSizeM2: 0,
      maxSizeM2: 1000000,
      propertyTypes: <String>{},
      preferredPropertyTypes: <String>{},
      conditions: <String>{},
      preferredConditions: <String>{},
      listingSource: ListingSourceFilter.any,
      minFloor: 0,
      moveInFilter: MoveInFilter.any,
      sortBy: SearchSortOption.bestMatch,
      includeUnknownPriceListings: false,
      customAreaPolygon: <LatLng>[],
      city: '',
      transactionType: TransactionTypeFilter.any,
    );
    setState(() {
      _locationCtrl.clear();
      _minRoomsCtrl.clear();
      _maxRoomsCtrl.clear();
      _draftFilters = resetFilters;
      _visibleCount = provider.filteredCountFor(resetFilters);
      _markerPreview = provider.previewFilteredProperties(resetFilters);
    });
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final f = _draftFilters;
        final area = f.hasCustomArea
            ? SearchArea.custom(polygon: f.customAreaPolygon)
            : provider.searchAreas.firstWhere(
                (item) => item.id == f.areaId,
                orElse: () => provider.selectedArea,
              );

        final locationQuery = _locationCtrl.text.trim().toLowerCase();
        final filteredCities = provider.availableCities
            .where((city) =>
                locationQuery.isEmpty ||
                city.toLowerCase().contains(locationQuery))
            .take(12)
            .toList();
        final filteredAreas = provider.searchAreas
            .where((a) =>
                locationQuery.isEmpty ||
                a.name.toLowerCase().contains(locationQuery))
            .where((a) => a.id != 'all_israel')
            .take(8)
            .toList();
        final locationSuggestions = <_LocationSuggestion>[
          ...filteredCities.map(
            (city) => _LocationSuggestion.city(context, city),
          ),
          ...filteredAreas.map(
            (searchArea) => _LocationSuggestion.area(context, searchArea),
          ),
        ];

        return Material(
          color: AppColors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.92,
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: Column(
                children: [
                  const SizedBox(height: 12),
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
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () {
                              markInAppBack();
                              Navigator.of(context).pop();
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(
                                color: AppColors.slate100,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close,
                                  size: 18, color: AppColors.navy),
                            ),
                          ),
                        ),
                        Text(
                          AppLocalizations.of(context)!
                              .discoverScreenA597b860,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.navy,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: 1,
                    color: AppColors.borderLight.withValues(alpha: 0.8),
                  ),
                  // Scrollable content
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                      children: [
                        // ── מטרה ──
                        _FilterSection(
                          title: AppLocalizations.of(context)!
                              .discoverScreen8aa21a4c,
                          icon: IconsaxPlusLinear.category,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _TransactionCard(
                              label: AppLocalizations.of(context)!
                                  .discoverScreen5f8fb8a5,
                              price: _transactionMetric(
                                provider,
                                f,
                                TransactionTypeFilter.any,
                              ),
                              isSelected: f.transactionType ==
                                  TransactionTypeFilter.any,
                              onTap: () {
                                _setDraftFilters(
                                  _filtersForTransaction(
                                    f,
                                    TransactionTypeFilter.any,
                                  ),
                                  provider,
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            _TransactionCard(
                              label: AppLocalizations.of(context)!
                                  .discoverScreen60d47dc4,
                              price: _transactionMetric(
                                provider,
                                f,
                                TransactionTypeFilter.rent,
                              ),
                              isSelected: f.transactionType ==
                                  TransactionTypeFilter.rent,
                              onTap: () {
                                _setDraftFilters(
                                  _filtersForTransaction(
                                    f,
                                    TransactionTypeFilter.rent,
                                  ),
                                  provider,
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            _TransactionCard(
                              label: AppLocalizations.of(context)!
                                  .discoverScreen40eb4dca,
                              price: _transactionMetric(
                                provider,
                                f,
                                TransactionTypeFilter.sale,
                              ),
                              isSelected: f.transactionType ==
                                  TransactionTypeFilter.sale,
                              onTap: () {
                                _setDraftFilters(
                                  _filtersForTransaction(
                                    f,
                                    TransactionTypeFilter.sale,
                                  ),
                                  provider,
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // ── תקציב ──
                        _FilterSection(
                          title: AppLocalizations.of(context)!
                              .discoverScreenC6c960c3,
                          icon: IconsaxPlusLinear.money,
                        ),
                        const SizedBox(height: 12),
                        _PriceHistogram(
                          minBudget: f.minBudget.toDouble().clamp(
                                _priceSliderMin(f.transactionType),
                                _priceSliderMax(f.transactionType),
                              ),
                          maxBudget: f.maxBudget.toDouble().clamp(
                                _priceSliderMin(f.transactionType),
                                _priceSliderMax(f.transactionType),
                              ),
                          sliderMin: _priceSliderMin(f.transactionType),
                          sliderMax: _priceSliderMax(f.transactionType),
                        ),
                        const SizedBox(height: 4),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            rangeThumbShape:
                                const _CustomRangeSliderThumbShape(),
                            activeTrackColor: AppColors.primary,
                            inactiveTrackColor: AppColors.border,
                          ),
                          child: RangeSlider(
                            values: RangeValues(
                              f.minBudget.toDouble().clamp(
                                  _priceSliderMin(f.transactionType),
                                  _priceSliderMax(f.transactionType)),
                              f.maxBudget.toDouble().clamp(
                                  _priceSliderMin(f.transactionType),
                                  _priceSliderMax(f.transactionType)),
                            ),
                            min: _priceSliderMin(f.transactionType),
                            max: _priceSliderMax(f.transactionType),
                            divisions: _priceSliderDivisions(f.transactionType),
                            onChanged: (values) => _setDraftFilters(
                              f.copyWith(
                                minBudget: _roundedPriceForTransaction(
                                  f.transactionType,
                                  values.start,
                                ),
                                maxBudget: _roundedPriceForTransaction(
                                  f.transactionType,
                                  values.end,
                                ),
                              ),
                              provider,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _PriceInputCard(
                              label: AppLocalizations.of(context)!
                                  .discoverScreen7a683618,
                              value: _formatCurrency(f.minBudget.round()),
                              onTap: () => _editRangeValues(
                                context: context,
                                title: _priceFilterLabel(context),
                                initialMinValue: f.minBudget.toString(),
                                initialMaxValue: f.maxBudget.toString(),
                                suffix: '₪',
                                keyboardType: TextInputType.number,
                                onSubmitted: (minRaw, maxRaw) {
                                  final minParsed = int.tryParse(
                                    minRaw.replaceAll(RegExp(r'[^0-9]'), ''),
                                  );
                                  final maxParsed = maxRaw.trim().isEmpty
                                      ? 2000000000
                                      : int.tryParse(
                                          maxRaw.replaceAll(
                                              RegExp(r'[^0-9]'), ''),
                                        );
                                  if (minParsed == null || maxParsed == null) {
                                    return;
                                  }
                                  final sliderMin =
                                      _priceSliderMin(f.transactionType)
                                          .round();
                                  final clampedMin =
                                      _roundedPriceForTransaction(
                                    f.transactionType,
                                    math.max(sliderMin, minParsed).toDouble(),
                                  );
                                  final clampedMax =
                                      _roundedPriceForTransaction(
                                    f.transactionType,
                                    math.max(clampedMin, maxParsed).toDouble(),
                                  );
                                  _setDraftFilters(
                                    f.copyWith(
                                      minBudget: clampedMin,
                                      maxBudget: clampedMax,
                                    ),
                                    provider,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            _PriceInputCard(
                              label: AppLocalizations.of(context)!
                                  .discoverScreen6dd38cc5,
                              value: f.maxBudget >= 2000000000
                                  ? AppLocalizations.of(context)!
                                      .discoverScreen09ae3918
                                  : _formatCurrency(f.maxBudget.round()),
                              onTap: () => _editRangeValues(
                                context: context,
                                title: _priceFilterLabel(context),
                                initialMinValue: f.minBudget.toString(),
                                initialMaxValue: f.maxBudget.toString(),
                                suffix: '₪',
                                keyboardType: TextInputType.number,
                                onSubmitted: (minRaw, maxRaw) {
                                  final minParsed = int.tryParse(
                                    minRaw.replaceAll(RegExp(r'[^0-9]'), ''),
                                  );
                                  final maxParsed = maxRaw.trim().isEmpty
                                      ? 2000000000
                                      : int.tryParse(
                                          maxRaw.replaceAll(
                                              RegExp(r'[^0-9]'), ''),
                                        );
                                  if (minParsed == null || maxParsed == null) {
                                    return;
                                  }
                                  final sliderMin =
                                      _priceSliderMin(f.transactionType)
                                          .round();
                                  final clampedMin =
                                      _roundedPriceForTransaction(
                                    f.transactionType,
                                    math.max(sliderMin, minParsed).toDouble(),
                                  );
                                  final clampedMax =
                                      _roundedPriceForTransaction(
                                    f.transactionType,
                                    math.max(clampedMin, maxParsed).toDouble(),
                                  );
                                  _setDraftFilters(
                                    f.copyWith(
                                      minBudget: clampedMin,
                                      maxBudget: clampedMax,
                                    ),
                                    provider,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SwitchListTile.adaptive(
                          value: f.includeUnknownPriceListings,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            AppLocalizations.of(context)!
                                .discoverScreenFe578531,
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            AppLocalizations.of(context)!
                                .discoverScreen25ade83a,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          onChanged: (value) => _setDraftFilters(
                            f.copyWith(includeUnknownPriceListings: value),
                            provider,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // ── חדרים ──
                        _FilterSection(
                          title: AppLocalizations.of(context)!
                              .discoverScreenB50b3974,
                          icon: IconsaxPlusLinear.home,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _minRoomsCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.navy,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(
                                      color: f.minRooms > 0
                                          ? AppColors.primary
                                          : AppColors.border,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(
                                      color: f.minRooms > 0
                                          ? AppColors.primary
                                          : AppColors.border,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                                  ),
                                  hintText: AppLocalizations.of(context)!
                                      .discoverScreenC1779315,
                                  hintStyle: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                onChanged: (v) {
                                  if (v.isEmpty) {
                                    _setDraftFilters(f.copyWith(minRooms: 0.0), provider);
                                    return;
                                  }
                                  final min = double.tryParse(v);
                                  if (min != null) {
                                    _setDraftFilters(f.copyWith(minRooms: min.clamp(0.0, 20.0)), provider);
                                  }
                                },
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                '—',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _maxRoomsCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.navy,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(
                                      color: f.maxRooms < 10
                                          ? AppColors.primary
                                          : AppColors.border,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(
                                      color: f.maxRooms < 10
                                          ? AppColors.primary
                                          : AppColors.border,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                                  ),
                                  hintText: AppLocalizations.of(context)!
                                      .discoverScreen344c1d0e,
                                  hintStyle: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                onChanged: (v) {
                                  if (v.isEmpty) {
                                    _setDraftFilters(f.copyWith(maxRooms: 10.0), provider);
                                    return;
                                  }
                                  final max = double.tryParse(v);
                                  if (max != null) {
                                    _setDraftFilters(f.copyWith(maxRooms: max.clamp(0.0, 20.0)), provider);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // ── מיקום (עיר + אזור) ──
                        _FilterSection(
                          title: AppLocalizations.of(context)!
                              .discoverScreen26d0e7de,
                          icon: IconsaxPlusLinear.location,
                          action: (f.city.isNotEmpty ||
                                  f.areaId != 'all_israel' ||
                                  f.hasCustomArea)
                              ? TextButton(
                                  onPressed: () {
                                    setState(() => _locationCtrl.clear());
                                    _setDraftFilters(
                                      f.copyWith(
                                        city: '',
                                        areaId: 'all_israel',
                                        customAreaPolygon: const <LatLng>[],
                                      ),
                                      provider,
                                    );
                                  },
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    foregroundColor: AppColors.primary,
                                  ),
                                  child: Text(AppLocalizations.of(context)!
                                      .discoverScreen5f8fb8a5),
                                )
                              : null,
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Row(
                            children: [
                              const SizedBox(width: 10),
                              const RentlyIcon(
                                IconsaxPlusLinear.search_normal,
                                size: 18,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _locationCtrl,
                                  onChanged: (v) => setState(() {}),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.navy,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: AppLocalizations.of(context)!
                                        .discoverScreenE65e9ceb,
                                    hintStyle: TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textSecondary
                                          .withValues(alpha: 0.72),
                                      fontWeight: FontWeight.w600,
                                    ),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                              if (_locationCtrl.text.isNotEmpty)
                                IconButton(
                                  icon: const RentlyIcon(
                                    IconsaxPlusLinear.close_circle,
                                    size: 18,
                                    color: AppColors.textSecondary,
                                  ),
                                  onPressed: () {
                                    setState(() => _locationCtrl.clear());
                                    _setDraftFilters(
                                      f.copyWith(
                                        city: '',
                                        areaId: 'all_israel',
                                        customAreaPolygon: const <LatLng>[],
                                      ),
                                      provider,
                                    );
                                  },
                                ),
                              Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                  color: AppColors.slate100,
                                  shape: BoxShape.circle,
                                ),
                                child: const RentlyIcon(
                                  IconsaxPlusLinear.location,
                                  size: 18,
                                  color: AppColors.navy,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            reverse: true,
                            child: Row(
                              children: [
                                for (final city in [
                                  AppLocalizations.of(context)!
                                      .discoverScreen2c1f2bbd,
                                  AppLocalizations.of(context)!
                                      .discoverScreen8e0dfe1e,
                                  AppLocalizations.of(context)!
                                      .discoverScreenCa1cc213,
                                  AppLocalizations.of(context)!
                                      .discoverScreenEa980134,
                                  AppLocalizations.of(context)!
                                      .discoverScreen2231ce66,
                                  AppLocalizations.of(context)!
                                      .discoverScreen982e0598,
                                  AppLocalizations.of(context)!
                                      .discoverScreen96a73cd7,
                                ]) ...[
                                  _FilterLocationPill(
                                    label: city,
                                    isSelected: f.city == city,
                                    onTap: () {
                                      final nextCity =
                                          f.city == city ? '' : city;
                                      setState(() {
                                        _locationCtrl.text = nextCity;
                                      });
                                      _setDraftFilters(
                                        f.copyWith(
                                          city: nextCity,
                                          areaId: 'all_israel',
                                          customAreaPolygon: const <LatLng>[],
                                        ),
                                        provider,
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                ]
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (locationQuery.isNotEmpty &&
                            locationSuggestions.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              AppLocalizations.of(context)!
                                  .discoverScreen835a122a,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (locationQuery.isNotEmpty &&
                            locationSuggestions.isNotEmpty)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.borderLight),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.navy.withValues(alpha: 0.04),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                for (var i = 0;
                                    i < locationSuggestions.length;
                                    i++)
                                  _LocationSuggestionTile(
                                    suggestion: locationSuggestions[i],
                                    isSelected: locationSuggestions[i].isCity
                                        ? f.city == locationSuggestions[i].label
                                        : f.areaId ==
                                            locationSuggestions[i].area!.id,
                                    showDivider:
                                        i != locationSuggestions.length - 1,
                                    onTap: () {
                                      final suggestion = locationSuggestions[i];
                                      setState(() {
                                        _locationCtrl.text = suggestion.label;
                                      });
                                      if (suggestion.isCity) {
                                        _setDraftFilters(
                                          f.copyWith(
                                            city: suggestion.label,
                                            areaId: 'all_israel',
                                            customAreaPolygon: const <LatLng>[],
                                          ),
                                          provider,
                                        );
                                        return;
                                      }
                                      _setDraftFilters(
                                        f.copyWith(
                                          city: '',
                                          areaId: suggestion.area!.id,
                                          customAreaPolygon: const <LatLng>[],
                                        ),
                                        provider,
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 24),
                        // ── מיון ──
                        _FilterSection(
                            title: AppLocalizations.of(context)!
                                .discoverScreen1df7e5cb,
                            icon: IconsaxPlusLinear.sort),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: Row(
                            children: SearchSortOption.values.map((option) {
                              final selected = f.sortBy == option;
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: GestureDetector(
                                  onTap: () => _setDraftFilters(
                                    f.copyWith(sortBy: option),
                                    provider,
                                  ),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? AppColors.primary
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: selected
                                            ? AppColors.primary
                                            : AppColors.borderLight,
                                      ),
                                      boxShadow: selected
                                          ? [
                                              BoxShadow(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.22),
                                                blurRadius: 8,
                                                offset: const Offset(0, 4),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _sortIcon(option),
                                          size: 13,
                                          color: selected
                                              ? Colors.white
                                              : AppColors.navy,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _sortLabel(context, option),
                                          style: TextStyle(
                                            color: selected
                                                ? Colors.white
                                                : AppColors.navy,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // ── גודל ──
                        _RangeSliderField(
                          label: AppLocalizations.of(context)!
                              .discoverScreen0f95260b,
                          icon: IconsaxPlusLinear.maximize_4,
                          values: RangeValues(
                            f.minSizeM2.toDouble().clamp(0, 2000),
                            f.maxSizeM2.toDouble().clamp(0, 2000),
                          ),
                          min: 0,
                          max: 2000,
                          divisions: 200,
                          displayValue: _sizeDisplayValue(
                              context, f.minSizeM2, f.maxSizeM2),
                          onValueTap: () => _editRangeValues(
                            context: context,
                            title: AppLocalizations.of(context)!
                                .discoverScreen0f95260b,
                            initialMinValue: f.minSizeM2.toString(),
                            initialMaxValue: f.maxSizeM2 >= 1000000
                                ? ''
                                : f.maxSizeM2.toString(),
                            suffix: AppLocalizations.of(context)!
                                .discoverScreen608912c9,
                            keyboardType: TextInputType.number,
                            onSubmitted: (minRaw, maxRaw) {
                              final minParsed = int.tryParse(
                                minRaw.replaceAll(RegExp(r'[^0-9]'), ''),
                              );
                              final maxParsed = maxRaw.trim().isEmpty
                                  ? 1000000
                                  : int.tryParse(
                                      maxRaw.replaceAll(RegExp(r'[^0-9]'), ''),
                                    );
                              if (minParsed == null || maxParsed == null)
                                return;
                              final minSize = math.max(0, minParsed);
                              final maxSize = math.max(minSize, maxParsed);
                              _setDraftFilters(
                                f.copyWith(
                                  minSizeM2: minSize,
                                  maxSizeM2: maxSize,
                                ),
                                provider,
                              );
                            },
                          ),
                          onChanged: (values) {
                            final minSize = values.start.round();
                            final maxSize = values.end.round() >= 2000
                                ? 1000000
                                : values.end.round();
                            _setDraftFilters(
                              f.copyWith(
                                minSizeM2: minSize,
                                maxSizeM2: maxSize,
                              ),
                              provider,
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        // ── קומה ──
                        _SliderField(
                          label: AppLocalizations.of(context)!
                              .discoverScreenC67e3688,
                          icon: IconsaxPlusLinear.building,
                          value: f.minFloor.toDouble(),
                          min: 0,
                          max: 30,
                          divisions: 30,
                          displayValue: f.minFloor == 0
                              ? AppLocalizations.of(context)!
                                  .discoverScreen09ae3918
                              : AppLocalizations.of(context)!
                                  .discoverScreenB42b537d(f.minFloor),
                          onValueTap: () => _editSliderValue(
                            context: context,
                            title: AppLocalizations.of(context)!
                                .discoverScreenC67e3688,
                            initialValue:
                                f.minFloor == 0 ? '' : '${f.minFloor}',
                            suffix: '',
                            keyboardType: TextInputType.number,
                            onSubmitted: (raw) {
                              final parsed = raw.trim().isEmpty
                                  ? 0
                                  : int.tryParse(
                                      raw.replaceAll(RegExp(r'[^0-9]'), ''),
                                    );
                              if (parsed == null) return;
                              _setDraftFilters(
                                f.copyWith(minFloor: math.max(0, parsed)),
                                provider,
                              );
                            },
                          ),
                          onChanged: (value) => _setDraftFilters(
                            f.copyWith(minFloor: value.round()),
                            provider,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // ── סוג נכס ──
                        _FilterSection(
                          title: AppLocalizations.of(context)!
                              .discoverScreen7d93908e,
                          icon: IconsaxPlusLinear.building,
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: Row(
                            children:
                                provider.availablePropertyTypes.map((type) {
                              final state = f.propertyTypeState(type);
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: _PropertyTypeCard(
                                  label: type,
                                  state: state,
                                  icon: _propertyTypeIcon(type),
                                  onTap: () => _handlePriorityTap(
                                    key: 'type:$type',
                                    current: state,
                                    onSelected: (priority) => _setDraftFilters(
                                      f.setPropertyTypeState(type, priority),
                                      provider,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // ── מצב הנכס ──
                        _FilterSection(
                          title: AppLocalizations.of(context)!
                              .discoverScreen357b4923,
                          icon: IconsaxPlusLinear.shield_tick,
                          action: _PriorityLegend(),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              provider.availableConditions.map((condition) {
                            final state = f.conditionState(condition);
                            return _PriorityFilterChip(
                              label: condition,
                              state: state,
                              icon: IconsaxPlusLinear.shield_tick,
                              onTap: () => _handlePriorityTap(
                                key: 'condition:$condition',
                                current: state,
                                onSelected: (priority) => _setDraftFilters(
                                  f.setConditionState(condition, priority),
                                  provider,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                        // ── מקור מודעה ──
                        _FilterSection(
                          title: AppLocalizations.of(context)!
                              .discoverScreen5aa1c77f,
                          icon: IconsaxPlusLinear.profile_2user,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ListingSourceFilter.values
                              .where(
                                  (source) => source != ListingSourceFilter.any)
                              .map((source) {
                            final state = f.listingSourceState(source);
                            return _PriorityFilterChip(
                              label: _listingSourceLabel(context, source),
                              state: state,
                              icon: _listingSourceIcon(source),
                              onTap: () => _handlePriorityTap(
                                key: 'listing-source:${source.name}',
                                current: state,
                                onSelected: (priority) => _setDraftFilters(
                                  f.setListingSourceState(source, priority),
                                  provider,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          AppLocalizations.of(context)!
                              .discoverScreenF7fab77d,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // ── מועד כניסה ──
                        _FilterSection(
                          title: AppLocalizations.of(context)!
                              .discoverScreen1399cd87,
                          icon: IconsaxPlusLinear.calendar_1,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: MoveInFilter.values
                              .where((option) => option != MoveInFilter.any)
                              .map((option) {
                            final state = f.moveInState(option);
                            return _PriorityFilterChip(
                              label: _moveInLabel(context, option),
                              state: state,
                              icon: IconsaxPlusLinear.calendar_1,
                              onTap: () => _handlePriorityTap(
                                key: 'move-in:${option.name}',
                                current: state,
                                onSelected: (priority) => _setDraftFilters(
                                  f.setMoveInState(option, priority),
                                  provider,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          AppLocalizations.of(context)!
                              .discoverScreen14a99444,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // ── מאפיינים ──
                        Builder(
                          builder: (context) {
                            final selectedCount = provider.availableFeatures
                                .where((f2) =>
                                    f.featureState(f2) != FilterPriority.none)
                                .length;
                            return _FilterSection(
                              title: AppLocalizations.of(context)!
                                  .discoverScreen64680a66,
                              icon: IconsaxPlusLinear.filter,
                              badge:
                                  selectedCount > 0 ? '$selectedCount' : null,
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: provider.availableFeatures
                              .map((feature) {
                            final state = f.featureState(feature);
                            return _PriorityFilterChip(
                              label: PropertyFeatureCatalog.labelFor(
                                AppLocalizations.of(context)!,
                                feature,
                              ),
                              state: state,
                              icon: _featureIcon(feature),
                              onTap: () {
                                _handlePriorityTap(
                                  key: 'feature:$feature',
                                  current: state,
                                  onSelected: (priority) => _setDraftFilters(
                                    f.setFeatureState(feature, priority),
                                    provider,
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                        // ── מקומות בסביבה ──
                        _FilterSection(
                          title: AppLocalizations.of(context)!
                              .discoverScreen485ce069,
                          icon: IconsaxPlusLinear.location,
                          badge: f.preferredNearby.isNotEmpty
                              ? '${f.preferredNearby.length}'
                              : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                              right: 2, top: 2, bottom: 10),
                          child: Text(
                            AppLocalizations.of(context)!
                                .discoverScreen6ca5e778,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final opt in _nearbyPrefOptions(context))
                              _NearbyKindChip(
                                label: opt.$2,
                                icon: opt.$3,
                                selected: f.preferredNearby.contains(opt.$1),
                                onTap: () => _setDraftFilters(
                                  f.toggleNearby(opt.$1),
                                  provider,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Footer
                  Container(
                    padding: EdgeInsets.fromLTRB(
                        20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -4),
                        ),
                      ],
                      border: const Border(
                        top: BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (!provider.isLandlord) ...[
                          Flexible(
                            child: _SaveSearchButton(
                              onTap: () => _saveCurrentSearch(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              _resetFilters(provider);
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              AppLocalizations.of(context)!
                                  .discoverScreenEbbc108b,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: () {
                              _didCommit = true;
                              unawaited(provider.updateFilters(_draftFilters));
                              Navigator.of(context).pop();
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(
                                opacity: anim,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.3),
                                    end: Offset.zero,
                                  ).animate(anim),
                                  child: child,
                                ),
                              ),
                              child: Text(
                                AppLocalizations.of(context)!
                                    .discoverScreen51d46fb2(_visibleCount),
                                key: ValueKey(_visibleCount),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
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
      },
    );
  }
}

class _FilterSection extends StatelessWidget {
  _FilterSection(
      {required this.title, this.icon, this.action, this.badge});
  final String title;
  final IconData? icon;
  final Widget? action;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
        ],
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badge!,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
        if (action != null) ...[
          const Spacer(),
          action!,
        ],
      ],
    );
  }
}

class _PriorityLegend extends StatelessWidget {
  _PriorityLegend();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LegendChip(
          label: AppLocalizations.of(context)!.discoverScreen0a12cf33,
          color: AppColors.primary,
          icon: Icons.favorite_rounded,
        ),
        const SizedBox(width: 8),
        _LegendChip(
          label: AppLocalizations.of(context)!.discoverScreen19662bd6,
          color: AppColors.coral,
          icon: Icons.priority_high_rounded,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            AppLocalizations.of(context)!.discoverScreen4b54025b,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: Colors.white),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Uses a chip surface, while tap interpretation is handled by the sheet state
/// so single tap can mean "preferred" and a quick second tap can upgrade it to
/// "required".
class _PriorityFilterChip extends StatelessWidget {
  _PriorityFilterChip({
    required this.label,
    required this.state,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final FilterPriority state;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isActive = state != FilterPriority.none;
    final bool isRequired = state == FilterPriority.required;

    final Color activeColor = isRequired ? AppColors.coral : AppColors.primary;
    final Color labelColor = isActive ? Colors.white : AppColors.navy;

    return FilterChip(
      selected: isActive,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: activeColor,
      backgroundColor: AppColors.primaryLight2,
      side: BorderSide(
        color: isActive ? activeColor : AppColors.borderLight,
        width: 1.5,
      ),
      elevation: isActive ? 3 : 0,
      pressElevation: 4,
      shadowColor:
          isActive ? activeColor.withValues(alpha: 0.35) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: labelColor),
          const SizedBox(width: 4),
          Text(label),
          if (state == FilterPriority.preferred) ...[
            const SizedBox(width: 4),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite_rounded,
                  size: 8, color: Colors.white),
            ),
          ],
          if (state == FilterPriority.required) ...[
            const SizedBox(width: 4),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.priority_high_rounded,
                  size: 8, color: Colors.white),
            ),
          ],
        ],
      ),
      labelStyle: TextStyle(
        color: labelColor,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    );
  }
}

class _SliderField extends StatelessWidget {
  _SliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onChanged,
    this.onValueTap,
    this.icon,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;
  final VoidCallback? onValueTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: AppColors.navy),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy),
            ),
            const Spacer(),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onValueTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          displayValue,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      RentlyIcon(
                        IconsaxPlusLinear.edit_2,
                        size: 14,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _RangeSliderField extends StatelessWidget {
  _RangeSliderField({
    required this.label,
    required this.values,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onChanged,
    this.onValueTap,
    this.icon,
  });

  final String label;
  final RangeValues values;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<RangeValues> onChanged;
  final VoidCallback? onValueTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final safeStart = values.start.clamp(min, max);
    final safeEnd = values.end.clamp(safeStart, max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: AppColors.navy),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const Spacer(),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onValueTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          displayValue,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      RentlyIcon(
                        IconsaxPlusLinear.edit_2,
                        size: 14,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        RangeSlider(
          values: RangeValues(safeStart, safeEnd),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _AreaLassoScreen extends StatefulWidget {
  _AreaLassoScreen({
    required this.initialArea,
    required this.initialPolygon,
    required this.previewMarkers,
    required this.filters,
  });

  final SearchArea initialArea;
  final List<LatLng> initialPolygon;
  // Snapshot for the very first frame; live markers are recomputed from the
  // provider each build (so a newly uploaded property shows up immediately).
  final List<RentalProperty> previewMarkers;
  final SearchFilters filters;

  @override
  State<_AreaLassoScreen> createState() => _AreaLassoScreenState();
}

class _AreaLassoScreenState extends State<_AreaLassoScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final List<LatLng> _currentPolygon = <LatLng>[];
  Offset? _lastDrawOffset;
  bool _drawMode = false; // Lasso mode active by default
  RentalProperty? _selectedProperty;
  bool _cardsCollapsed = false; // the bottom property strip can be dragged down
  final ScrollController _scrollController = ScrollController();

  // Live property list, refreshed from the provider on every build so new
  // uploads appear without reopening the map.
  late List<RentalProperty> _markers;

  List<LatLng> get _activePolygon => _currentPolygon;

  @override
  void initState() {
    super.initState();
    _markers = widget.previewMarkers;
    // Default select the first property marker to show the bottom card initially
    _selectedProperty = widget.previewMarkers.firstOrNull;
    _currentPolygon.addAll(widget.initialPolygon);
    // Open focused on what matters — the drawn area if one exists, otherwise
    // the listings themselves. The old fixed nation-wide zoom opened on a
    // single unreadable clump of overlapping pins.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final points = _currentPolygon.length >= 3
          ? List<LatLng>.from(_currentPolygon)
          : _markers.map((p) => p.point).toList();
      if (points.length < 2) return;
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.fromLTRB(48, 140, 48, 200),
          maxZoom: 13,
        ),
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    final camera = _mapController.camera;
    final latTween = Tween<double>(
        begin: camera.center.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(
        begin: camera.center.longitude, end: destLocation.longitude);
    final zoomTween = Tween<double>(begin: camera.zoom, end: destZoom);

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    final animation =
        CurvedAnimation(parent: controller, curve: Curves.fastOutSlowIn);

    controller.addListener(() {
      if (!mounted) return;
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
      } else if (status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  void _selectProperty(RentalProperty property) {
    setState(() {
      _selectedProperty = property;
    });
    _animatedMapMove(property.point, 13.5);

    // Scroll horizontal card slider to the selected card
    final index = _markers.indexWhere((p) => p.id == property.id);
    if (index != -1 && _scrollController.hasClients) {
      // 280 is card width + 12 is separation
      _scrollController.animateTo(
        index * (280.0 + 12.0),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  int _activePointers = 0;

  void _startLasso(PointerDownEvent event) {
    _activePointers++;
    // A second finger (pinch-zoom) must never wipe an area the user already
    // drew — just stop the current stroke and let the zoom happen.
    if (!_drawMode || _activePointers > 1) {
      if (_activePointers > 1) setState(() => _lastDrawOffset = null);
      return;
    }
    final point =
        _mapController.camera.screenOffsetToLatLng(event.localPosition);
    setState(() {
      _currentPolygon
        ..clear()
        ..add(point);
      _lastDrawOffset = event.localPosition;
    });
  }

  void _updateLasso(PointerMoveEvent event) {
    if (!_drawMode || _activePointers > 1 || _lastDrawOffset == null) return;
    if ((event.localPosition - _lastDrawOffset!).distance < 10) return;
    final point =
        _mapController.camera.screenOffsetToLatLng(event.localPosition);
    setState(() {
      _currentPolygon.add(point);
      _lastDrawOffset = event.localPosition;
    });
  }

  void _finishLasso(PointerUpEvent event) {
    _activePointers = math.max(0, _activePointers - 1);
    if (!_drawMode) return;
    setState(() {
      _lastDrawOffset = null;
      // Lifting the finger with a real shape drawn = done. Exit draw mode so
      // the map pans normally again — a non-technical user should never be
      // stuck in a mode where dragging the map "doesn't work".
      if (_currentPolygon.length >= 3) {
        _drawMode = false;
        HapticFeedback.lightImpact();
      }
    });
  }

  void _cancelLasso(PointerCancelEvent event) {
    _activePointers = math.max(0, _activePointers - 1);
    setState(() => _lastDrawOffset = null);
  }

  // Fit the camera around every visible pin ("show me everything") — honest,
  // unlike the old GPS-looking button that teleported to an arbitrary listing.
  void _showAllProperties() {
    if (_markers.isEmpty) {
      _animatedMapMove(widget.initialArea.center, 12.5);
      return;
    }
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: _markers.map((p) => p.point).toList(),
        padding: const EdgeInsets.fromLTRB(48, 140, 48, 200),
        maxZoom: 14,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Recompute the visible properties from the live catalogue → a property a
    // landlord just uploaded (or any catalogue refresh) shows up immediately.
    // Cap the map pins: each marker loads a network image, so 500 of them made the
    // screen crawl. ~70 is plenty for an area overview + drawing a lasso.
    _markers = context
        .watch<DatingProvider>()
        .previewFilteredProperties(widget.filters, limit: 70);
    final polygon = _activePolygon;
    final hasProperties = _markers.isNotEmpty;
    final hasPolygon = polygon.length >= 3;
    // Honest count: how many of the visible pins actually fall inside the
    // drawn shape (the old chip showed the whole map's count regardless).
    final drawnArea =
        hasPolygon ? SearchArea.custom(polygon: polygon) : null;
    // Count against the FULL filtered catalogue, not the 70 pins shown — the
    // pin cap is a rendering optimisation and must not skew the number the
    // user acts on. Skipped mid-stroke (_lastDrawOffset != null) to keep
    // drawing at full frame rate.
    final countSource = (drawnArea != null && _lastDrawOffset == null)
        ? context
            .read<DatingProvider>()
            .previewFilteredProperties(widget.filters, limit: 5000)
        : _markers;
    final inAreaCount = drawnArea == null
        ? 0
        : countSource.where((p) => drawnArea.contains(p.point)).length;
    final canSave = hasPolygon && inAreaCount > 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Flutter Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.initialArea.center,
              initialZoom: widget.initialArea.id == 'all_israel' ? 7.5 : 12.5,
              interactionOptions: InteractionOptions(
                flags: _drawMode
                    ? InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom
                    : InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.rentch.app',
              ),
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: widget.initialArea.polygon,
                    color: AppColors.navy.withValues(alpha: 0.04),
                    borderColor: AppColors.navy.withValues(alpha: 0.12),
                    borderStrokeWidth: 1.4,
                  ),
                  if (hasPolygon)
                    Polygon(
                      points: polygon,
                      color: AppColors.primary.withValues(alpha: 0.18),
                      borderColor: AppColors.primary,
                      borderStrokeWidth: 2.8,
                    ),
                ],
              ),
              // Markers Layer: Circular Image Thumbnails inspired by mockup
              MarkerLayer(
                // Lightweight PRICE PINS (no per-marker network image) so the map
                // paints instantly — the photo shows in the bottom card once a
                // pin is selected. (Photo-bubble markers previously downloaded up
                // to 70 CDN images on every open, with no disk cache → very slow.)
                markers: _markers.map(
                  (property) {
                    final isSelected = property.id == _selectedProperty?.id;
                    final bg = isSelected ? AppColors.blue : Colors.white;
                    final fg = isSelected ? Colors.white : AppColors.navy;
                    return Marker(
                      point: property.point,
                      width: isSelected ? 96 : 84,
                      height: isSelected ? 46 : 40,
                      child: GestureDetector(
                        onTap: () => _selectProperty(property),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.blue
                                      : Colors.white,
                                  width: 2.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    blurRadius: isSelected ? 8 : 4,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Text(
                                _pinPriceLabel(property),
                                style: TextStyle(
                                  color: fg,
                                  fontSize: isSelected ? 14 : 12.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            CustomPaint(
                              size: const Size(10, 6),
                              painter: _TrianglePainter(color: bg),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ).toList(),
              ),
            ],
          ),

          // Lasso draw listener
          if (_drawMode)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _startLasso,
                onPointerMove: _updateLasso,
                onPointerUp: _finishLasso,
                onPointerCancel: _cancelLasso,
              ),
            ),

          // Top Search Bar & Circular Control Buttons
          Positioned(
            top: 16 + MediaQuery.of(context).padding.top,
            left: 16,
            right: 16,
            child: Row(
              children: [
                // Back Button
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.navy),
                    onPressed: () {
                      markInAppBack();
                      Navigator.of(context).pop();
                    },
                  ),
                ),
                // Filter button — opens the filter sheet directly. (Was a fake
                // dropdown where every menu item opened the same sheet anyway —
                // one pointless extra tap for the user.)
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      final provider =
                          Provider.of<DatingProvider>(context, listen: false);
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => _FiltersSheet(provider: provider),
                      );
                    },
                    child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: AppColors.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            const RentlyIcon(
                              IconsaxPlusLinear.setting_4,
                              size: 18,
                              color: AppColors.navy,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.initialArea.id == 'all_israel'
                                    ? AppLocalizations.of(context)!
                                        .discoverScreen9ad9fd5e
                                    : AppLocalizations.of(context)!
                                        .discoverScreen8853fa88(
                                            widget.initialArea.name),
                                style: const TextStyle(
                                  color: AppColors.navy,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: AppColors.navy,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                // "Show everything" button — fits the camera around all pins.
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    tooltip:
                        AppLocalizations.of(context)!.lassoShowAllTooltip,
                    icon: const Icon(Icons.zoom_out_map_rounded,
                        color: AppColors.navy),
                    onPressed: _showAllProperties,
                  ),
                ),
              ],
            ),
          ),

          // While drawing: a clear instruction pill so the "map stopped
          // moving" state is never a mystery.
          if (_drawMode)
            Positioned(
              top: 84 + MediaQuery.of(context).padding.top,
              left: 24,
              right: 24,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.draw_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          AppLocalizations.of(context)!.lassoDrawPrompt,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Honest in-area count chip — only shown once a shape exists, and
          // counts what is actually inside it (the old chip showed the whole
          // map's count and doubled as a hidden save button).
          if (hasPolygon)
            Positioned(
              left: 16,
              right: 16,
              bottom: 368 + MediaQuery.of(context).padding.bottom,
              child: IgnorePointer(
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                          sigmaX: PlatformFx.blurSigma(12),
                          sigmaY: PlatformFx.blurSigma(12)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.38),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Text(
                          inAreaCount > 0
                              ? AppLocalizations.of(context)!
                                  .lassoInAreaCount(inAreaCount)
                              : AppLocalizations.of(context)!.lassoEmptyArea,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 2. Carousel: Spans 100% edge-to-edge of the screen
          if (hasProperties)
            // The property strip can be dragged down to get it out of the way of
            // the map, and pulled/tapped back up. Collapsed → only a small handle
            // peeks at the bottom.
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: _cardsCollapsed
                  ? -(300 - 34) + 60 + MediaQuery.of(context).padding.bottom
                  : 60 + MediaQuery.of(context).padding.bottom,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v > 120) setState(() => _cardsCollapsed = true);
                  if (v < -120) setState(() => _cardsCollapsed = false);
                },
                onTap: _cardsCollapsed
                    ? () => setState(() => _cardsCollapsed = false)
                    : null,
                child: SizedBox(
                  height: 300,
                  child: Column(
                    children: [
                      // Drag handle (also tap-to-toggle).
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            setState(() => _cardsCollapsed = !_cardsCollapsed),
                        child: Container(
                          width: 46,
                          height: 22,
                          alignment: Alignment.center,
                          child: Container(
                            width: 40,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          controller: _scrollController,
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _markers.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final property = _markers[index];
                            final isSelected =
                                property.id == _selectedProperty?.id;
                            void openDetails() => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PropertyDetailScreen(
                                        property: property,
                                        entrySource: 'deck',
                                        entryRank: index),
                                  ),
                                );
                            return _PropertyPreviewCard(
                              property: property,
                              isSelected: isSelected,
                              // First tap centres the map; a second tap (already
                              // selected) opens the page — the arrow always opens.
                              onTap: () {
                                if (_selectedProperty?.id == property.id) {
                                  openDetails();
                                } else {
                                  _selectProperty(property);
                                }
                              },
                              onOpenDetails: openDetails,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 3. Bottom action row — ONE big labeled button drives the whole
          // flow (draw → done → show results), so nothing relies on decoding
          // a mystery icon. "Clear" appears only when there is something to
          // clear.
          Positioned(
            left: 16,
            right: 16,
            bottom: 4 + MediaQuery.of(context).padding.bottom,
            child: Row(
              children: [
                if (hasPolygon || _drawMode) ...[
                  Expanded(
                    flex: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                            sigmaX: PlatformFx.blurSigma(18),
                            sigmaY: PlatformFx.blurSigma(18)),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.24),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12)),
                          ),
                          child: TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _currentPolygon.clear();
                                _lastDrawOffset = null;
                                _drawMode = false;
                              });
                            },
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white, size: 18),
                            label: Text(
                              AppLocalizations.of(context)!
                                  .discoverScreenE8b3a3d5,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                // Primary: start drawing → (drawing…) → show N results.
                Expanded(
                  flex: 2,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                          sigmaX: PlatformFx.blurSigma(18),
                          sigmaY: PlatformFx.blurSigma(18)),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: hasPolygon
                              ? (canSave
                                  ? AppColors.sky.withValues(alpha: 0.85)
                                  : Colors.black.withValues(alpha: 0.18))
                              : (_drawMode
                                  ? Colors.black.withValues(alpha: 0.18)
                                  : AppColors.primary.withValues(alpha: 0.9)),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: canSave
                                ? AppColors.sky.withValues(alpha: 0.4)
                                : Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: TextButton.icon(
                          onPressed: () {
                            if (hasPolygon) {
                              if (canSave) {
                                Navigator.of(context)
                                    .pop(List<LatLng>.from(polygon));
                              }
                              return;
                            }
                            if (!_drawMode) {
                              HapticFeedback.lightImpact();
                              setState(() => _drawMode = true);
                            }
                          },
                          icon: Icon(
                            hasPolygon
                                ? Icons.check_circle_outline_rounded
                                : Icons.draw_rounded,
                            color: (hasPolygon && !canSave) || _drawMode
                                ? Colors.white.withValues(alpha: 0.55)
                                : Colors.white,
                            size: 18,
                          ),
                          label: Text(
                            hasPolygon
                                ? (canSave
                                    ? AppLocalizations.of(context)!
                                        .lassoShowResults(inAreaCount)
                                    : AppLocalizations.of(context)!
                                        .lassoEmptyArea)
                                : (_drawMode
                                    ? AppLocalizations.of(context)!
                                        .lassoDrawing
                                    : AppLocalizations.of(context)!
                                        .lassoDrawButton),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: (hasPolygon && !canSave) || _drawMode
                                  ? Colors.white.withValues(alpha: 0.75)
                                  : Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
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

// ─── Thumbnail ───────────────────────────────────────────────────────────────

class _PropertyThumb extends StatelessWidget {
  _PropertyThumb({required this.media});

  final PropertyMedia? media;

  @override
  Widget build(BuildContext context) {
    return SafeMedia(
      media: media,
      fallback: _fallback(),
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
    );
  }

  Widget _fallback() => Container(
        color: AppColors.primaryLight2,
        child: RentlyIcon(
          IconsaxPlusLinear.building,
          size: 42,
          color: AppColors.primary,
        ),
      );
}

class _PropertyPreviewCard extends StatelessWidget {
  _PropertyPreviewCard({
    required this.property,
    required this.isSelected,
    required this.onTap,
    required this.onOpenDetails,
  });

  final RentalProperty property;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final isRent = property.transactionType != PropertyTransactionType.sale;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.1),
              blurRadius: isSelected ? 16 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Full background property image
              _PropertyThumb(media: property.primaryMedia),

              // Top-Left transaction type glassmorphic pill
              Positioned(
                top: 12,
                left: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(8), sigmaY: PlatformFx.blurSigma(8)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      color: Colors.black.withValues(alpha: 0.45),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00FF66),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              isRent
                                  ? AppLocalizations.of(context)!
                                      .discoverScreenB336259f
                                  : AppLocalizations.of(context)!
                                      .discoverScreen609fac18,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Top-Right details open icon button
              Positioned(
                top: 12,
                right: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(8), sigmaY: PlatformFx.blurSigma(8)),
                    child: GestureDetector(
                      onTap: onOpenDetails,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.4),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: const Icon(
                          Icons.favorite_border_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom Glassmorphic Panel
              Positioned(
                bottom: 10,
                left: 10,
                right: 10,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(18), sigmaY: PlatformFx.blurSigma(18)),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.black
                          .withValues(alpha: 0.17), // 17% opacity base
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Price row with arrow
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    property.priceLabel,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    property.priceSuffixLabel,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.6),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              GestureDetector(
                                onTap: onOpenDetails,
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withValues(alpha: 0.16),
                                    border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.2)),
                                  ),
                                  child: const Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Address row
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                color: Colors.white.withValues(alpha: 0.7),
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  property.address,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Spec pills
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildSpecPill(
                                icon: Icons.meeting_room_outlined,
                                label: AppLocalizations.of(context)!
                                    .discoverScreenD886d07f(
                                        property.roomsLabel),
                              ),
                              _buildSpecPill(
                                icon: Icons.crop_free_rounded,
                                label: AppLocalizations.of(context)!
                                    .discoverScreenFdb4eac7(property.sizeM2),
                              ),
                              _buildSpecPill(
                                icon: Icons.layers_outlined,
                                label: property.floor.isEmpty
                                    ? AppLocalizations.of(context)!
                                        .discoverScreenCcc5c5a6
                                    : AppLocalizations.of(context)!
                                        .discoverScreenD068bb57(
                                            floorLabel(property.floor,
                                                AppLocalizations.of(context)!)),
                              ),
                            ],
                          ),
                        ],
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

  Widget _buildSpecPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 11),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UndoButton extends StatelessWidget {
  const _UndoButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RentlyIcon(IconsaxPlusLinear.undo,
                size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 5),
            Text(
              AppLocalizations.of(context)!.discoverScreenAac4e7a2,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMorePropertiesState extends StatelessWidget {
  _NoMorePropertiesState();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DatingProvider>();
    // Distinguish "you searched an area and there's nothing" (an OOPS empty state)
    // from "you swiped through everything" — the copy should match the situation.
    final city = provider.filters.city.trim();
    final hasActiveSearch = city.isNotEmpty ||
        provider.filters.maxBudget != 0 ||
        provider.filters.minRooms > 1;
    final l10n = AppLocalizations.of(context)!;
    final title = hasActiveSearch
        ? (city.isNotEmpty
            ? l10n.discoverScreenBed527df(city)
            : l10n.discoverScreenAd918daa)
        : l10n.discoverScreen0d8b5e54;
    final subtitle = hasActiveSearch
        ? l10n.discoverScreen2d250f3a
        : l10n.discoverScreen044d147e;

    // Top-aligned + scrollable so the quick actions sit high on the screen
    // (raised out of the way of the navbar) and always fit.
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 120, 24, 130),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: RentlyIcon(
                  hasActiveSearch
                      ? IconsaxPlusLinear.emoji_sad
                      : IconsaxPlusLinear.search_normal,
                  color: AppColors.primary,
                  size: 36,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.5,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 22),
            _QuickActionBtn(
              icon: IconsaxPlusLinear.money,
              label: l10n.discoverScreen30fb9443,
              onTap: () => provider.updateFilters(
                provider.filters.copyWith(
                  maxBudget: provider.filters.maxBudget + 500,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _QuickActionBtn(
              icon: IconsaxPlusLinear.home,
              label: l10n.discoverScreen76e4a755,
              onTap: () {
                if (provider.filters.minRooms > 1) {
                  provider.updateFilters(
                    provider.filters.copyWith(
                      minRooms: provider.filters.minRooms - 0.5,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 10),
            _QuickActionBtn(
              icon: IconsaxPlusLinear.maximize_4,
              label: l10n.discoverScreen00256770,
              onTap: () => provider.updateFilters(
                provider.filters.copyWith(
                  minSizeM2: provider.filters.minSizeM2 >= 20
                      ? provider.filters.minSizeM2 - 20
                      : 0,
                ),
              ),
            ),
            const SizedBox(height: 18),
            _QuickActionBtn(
              icon: IconsaxPlusLinear.undo,
              label: l10n.discoverScreenB80f7438,
              onTap: () => provider.resetPassed(),
              filled: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionBtn extends StatelessWidget {
  _QuickActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    if (filled) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: shape,
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          side: const BorderSide(color: AppColors.borderLight),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: shape,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _SkeletonDiscoverView extends StatefulWidget {
  const _SkeletonDiscoverView();

  @override
  State<_SkeletonDiscoverView> createState() => _SkeletonDiscoverViewState();
}

class _SkeletonDiscoverViewState extends State<_SkeletonDiscoverView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _shimmer = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 72, 18, 0),
        child: AnimatedBuilder(
          animation: _shimmer,
          builder: (context, _) {
            final base = Color.lerp(
              AppColors.border,
              AppColors.cloud,
              _shimmer.value,
            )!;
            final highlight = Color.lerp(
              AppColors.slate200,
              AppColors.slate100,
              _shimmer.value,
            )!;
            return Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(color: base),
                        Positioned(
                          bottom: 28,
                          left: 24,
                          right: 24,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                  height: 28,
                                  width: 140,
                                  decoration: BoxDecoration(
                                      color: highlight,
                                      borderRadius: BorderRadius.circular(8))),
                              const SizedBox(height: 10),
                              Container(
                                  height: 14,
                                  width: 200,
                                  decoration: BoxDecoration(
                                      color: highlight,
                                      borderRadius: BorderRadius.circular(6))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Container(
                    height: 52,
                    color: Color.lerp(base, highlight, 0.5),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _formatCurrency(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final remaining = raw.length - i;
    buffer.write(raw[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return '₪$buffer';
}

String _compactPriceLabel(int value) {
  if (value >= 1000000) {
    final millions = value / 1000000;
    final formatted = millions >= 10
        ? millions.toStringAsFixed(0)
        : millions.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    return '₪${formatted}M';
  }
  if (value >= 100000) {
    return '₪${(value / 1000).round()}K';
  }
  return _formatCurrency(value);
}

String _sortLabel(BuildContext context, SearchSortOption option) {
  final l10n = AppLocalizations.of(context)!;
  switch (option) {
    case SearchSortOption.bestMatch:
      return l10n.discoverScreen8b3c043a;
    case SearchSortOption.priceLowToHigh:
      return l10n.discoverScreen4b8d8771;
    case SearchSortOption.priceHighToLow:
      return l10n.discoverScreen0126181a;
    case SearchSortOption.newestEntry:
      return l10n.discoverScreenC2dd498c;
    case SearchSortOption.biggestFirst:
      return l10n.discoverScreen9613740e;
  }
}

String _listingSourceLabel(BuildContext context, ListingSourceFilter source) {
  final l10n = AppLocalizations.of(context)!;
  switch (source) {
    case ListingSourceFilter.any:
      return l10n.discoverScreen5f8fb8a5;
    case ListingSourceFilter.privateOnly:
      return l10n.discoverScreenAc35c5b6;
    case ListingSourceFilter.agencyOnly:
      return l10n.discoverScreen88edd37e;
  }
}

class _LocationSuggestion {
  const _LocationSuggestion._({
    required this.label,
    required this.icon,
    required this.caption,
    required this.isCity,
    this.area,
  });

  factory _LocationSuggestion.city(BuildContext context, String city) {
    return _LocationSuggestion._(
      label: city,
      icon: IconsaxPlusLinear.building,
      caption: AppLocalizations.of(context)!.discoverScreenB2136c90,
      isCity: true,
    );
  }

  factory _LocationSuggestion.area(BuildContext context, SearchArea area) {
    return _LocationSuggestion._(
      label: area.name,
      icon: IconsaxPlusLinear.location,
      caption: AppLocalizations.of(context)!.discoverScreen7c0e2040,
      isCity: false,
      area: area,
    );
  }

  final String label;
  final IconData icon;
  final String caption;
  final bool isCity;
  final SearchArea? area;
}

class _LocationSuggestionTile extends StatelessWidget {
  _LocationSuggestionTile({
    required this.suggestion,
    required this.isSelected,
    required this.onTap,
    required this.showDivider,
  });

  final _LocationSuggestion suggestion;
  final bool isSelected;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final titleColor = isSelected ? AppColors.primary : AppColors.navy;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight2 : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.14)
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    suggestion.icon,
                    color: titleColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.label,
                        style: TextStyle(
                          color: titleColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        suggestion.caption,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isSelected
                      ? IconsaxPlusLinear.tick_circle
                      : IconsaxPlusLinear.arrow_left_2,
                  color:
                      isSelected ? AppColors.primary : AppColors.textSecondary,
                  size: 18,
                ),
              ],
            ),
            if (showDivider)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Divider(height: 1, color: AppColors.borderLight),
              ),
          ],
        ),
      ),
    );
  }
}

String _priceFilterLabel(BuildContext context) =>
    AppLocalizations.of(context)!.discoverScreenE190c982;

/// Display label for the size range slider.
/// When maxSizeM2 is at or above the slider ceiling (2000) or "unlimited",
/// we show a "2,000+ מ"ר" label instead of the raw large number.
String _sizeDisplayValue(BuildContext context, int minSizeM2, int maxSizeM2) {
  final l10n = AppLocalizations.of(context)!;
  final minStr = minSizeM2 == 0 ? '0' : '$minSizeM2';
  if (maxSizeM2 >= 1000000) {
    return minSizeM2 == 0
        ? l10n.discoverScreen09ae3918
        : l10n.discoverScreen4ed4e191(minStr);
  }
  if (maxSizeM2 >= 2000) {
    return l10n.discoverScreen6ba19199(minStr);
  }
  return l10n.discoverScreen9a6ba180(minStr, maxSizeM2);
}

double _priceSliderMin(TransactionTypeFilter type) {
  switch (type) {
    case TransactionTypeFilter.any:
      return 600;
    case TransactionTypeFilter.rent:
      return 600;
    case TransactionTypeFilter.sale:
      return 100000;
  }
}

double _priceSliderMax(TransactionTypeFilter type) {
  switch (type) {
    case TransactionTypeFilter.any:
      return 40000;
    case TransactionTypeFilter.rent:
      return 40000;
    case TransactionTypeFilter.sale:
      return 10000000;
  }
}

int _priceSliderDivisions(TransactionTypeFilter type) {
  switch (type) {
    case TransactionTypeFilter.any:
      return 197;
    case TransactionTypeFilter.rent:
      return 197;
    case TransactionTypeFilter.sale:
      return 99;
  }
}

int _roundedPriceForTransaction(TransactionTypeFilter type, double value) {
  switch (type) {
    case TransactionTypeFilter.any:
      return (value / 200).round() * 200;
    case TransactionTypeFilter.rent:
      return (value / 200).round() * 200;
    case TransactionTypeFilter.sale:
      return (value / 100000).round() * 100000;
  }
}

String _moveInLabel(BuildContext context, MoveInFilter option) {
  final l10n = AppLocalizations.of(context)!;
  switch (option) {
    case MoveInFilter.any:
      return l10n.discoverScreen232628d0;
    case MoveInFilter.immediate:
      return l10n.discoverScreenD02986c3;
    case MoveInFilter.within30Days:
      return l10n.discoverScreen402285bd;
    case MoveInFilter.within90Days:
      return l10n.discoverScreen23bb912d;
  }
}

IconData _sortIcon(SearchSortOption option) {
  switch (option) {
    case SearchSortOption.priceLowToHigh:
      return IconsaxPlusLinear.sort;
    case SearchSortOption.priceHighToLow:
      return IconsaxPlusLinear.sort;
    case SearchSortOption.newestEntry:
      return IconsaxPlusLinear.calendar;
    case SearchSortOption.biggestFirst:
      return IconsaxPlusLinear.maximize_3;
    case SearchSortOption.bestMatch:
      return IconsaxPlusLinear.star;
  }
}

IconData _propertyTypeIcon(String type) {
  final lower = type.trim().toLowerCase();
  if (lower.contains('גג') ||
      lower.contains('פנטהאוז') ||
      lower.contains('דופלקס')) {
    return IconsaxPlusLinear.buildings;
  }
  if (lower.contains('גן') || lower.contains('חצר') || lower.contains('גינה')) {
    return IconsaxPlusLinear.map_1;
  }
  if (lower.contains('בית') ||
      lower.contains('קוטג') ||
      lower.contains('יחידת') ||
      lower.contains('סטודיו')) {
    return IconsaxPlusLinear.home;
  }
  return IconsaxPlusLinear.building;
}

IconData _listingSourceIcon(ListingSourceFilter source) {
  switch (source) {
    case ListingSourceFilter.any:
      return IconsaxPlusLinear.profile_2user;
    case ListingSourceFilter.privateOnly:
      return IconsaxPlusLinear.user;
    case ListingSourceFilter.agencyOnly:
      return IconsaxPlusLinear.buildings;
  }
}

IconData _featureIcon(String feature) {
  final lower = feature.trim().toLowerCase();
  if (lower.contains('מצלמות') || lower.contains('cctv')) return IconsaxPlusLinear.camera;
  if (lower.contains('אזעקה')) return IconsaxPlusLinear.shield_tick;
  if (lower.contains('אינטרקום')) return IconsaxPlusLinear.call;
  if (lower.contains('חשמל')) return IconsaxPlusLinear.flash;
  if (lower.contains('מים')) return IconsaxPlusLinear.layer;
  if (lower.contains('אור טבעי') || lower.contains('natural_light')) return IconsaxPlusLinear.sun_1;
  if (lower.contains('אזור שקט') || lower.contains('quiet')) return IconsaxPlusLinear.heart;
  if (lower.contains('חיות')) return IconsaxPlusLinear.heart;
  if (lower.contains('חניה') || lower.contains('parking')) return IconsaxPlusLinear.routing;
  if (lower.contains('כניסה מאובטחת') || lower.contains('secure_entrance')) return IconsaxPlusLinear.lock;
  if (lower.contains('תחבורה ציבורית') || lower.contains('public_transport')) return IconsaxPlusLinear.bus;
  if (lower.contains('ריהוט') || lower.contains('מרוהטת')) {
    return IconsaxPlusLinear.home;
  }
  if (lower.contains('מעלית')) return IconsaxPlusLinear.buildings;
  if (lower.contains('ממ"ד') || lower.contains('ממד')) {
    return IconsaxPlusLinear.shield_tick;
  }
  if (lower.contains('מזגן') || lower.contains('מיזוג')) {
    return IconsaxPlusLinear.layer;
  }
  if (lower.contains('מרפסת')) return IconsaxPlusLinear.layer;
  if (lower.contains('מחסן')) return IconsaxPlusLinear.lock;
  if (lower.contains('סורגים')) return IconsaxPlusLinear.lock;
  if (lower.contains('נגישות')) return IconsaxPlusLinear.profile_circle;
  if (lower.contains('גינה') || lower.contains('חצר')) {
    return IconsaxPlusLinear.map;
  }
  if (lower.contains('שומר')) {
    return IconsaxPlusLinear.shield_tick;
  }
  if (lower.contains('משופצת') || lower.contains('משופץ')) {
    return IconsaxPlusLinear.setting_4;
  }
  return IconsaxPlusLinear.hashtag;
}

class _FilterLocationPill extends StatelessWidget {
  const _FilterLocationPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.navy : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? AppColors.navy : AppColors.border,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.navy,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CustomRangeSliderThumbShape extends RangeSliderThumbShape {
  const _CustomRangeSliderThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isPressed) {
    return const Size(28, 28);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    bool isEnabled = true,
    bool isOnTop = false,
    bool isPressed = false,
    required SliderThemeData sliderTheme,
    TextDirection? textDirection,
    Thumb? thumb,
  }) {
    final Canvas canvas = context.canvas;

    final Path shadowPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: 14));
    canvas.drawShadow(shadowPath, Colors.black, 4, true);

    final Paint fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 13, fillPaint);

    final Paint borderPaint = Paint()
      ..color = AppColors.navy
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, 13, borderPaint);

    final Paint linePaint = Paint()
      ..color = AppColors.navy
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(center.dx - 5, center.dy - 2),
        Offset(center.dx + 5, center.dy - 2), linePaint);
    canvas.drawLine(Offset(center.dx - 5, center.dy + 2),
        Offset(center.dx + 5, center.dy + 2), linePaint);
  }
}

class _TransactionCard extends StatelessWidget {
  _TransactionCard({
    required this.label,
    required this.price,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String price;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.navy : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppColors.navy : AppColors.borderLight,
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.navy.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.7)
                            : AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (isSelected)
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 11,
                        color: Colors.white,
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight2,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.discoverScreen5d2540f2,
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                price,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.2,
                  fontWeight: FontWeight.w900,
                  color: isSelected ? Colors.white : AppColors.navy,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceHistogram extends StatelessWidget {
  _PriceHistogram({
    required this.minBudget,
    required this.maxBudget,
    required this.sliderMin,
    required this.sliderMax,
  });

  final double minBudget;
  final double maxBudget;
  final double sliderMin;
  final double sliderMax;

  @override
  Widget build(BuildContext context) {
    const heights = [
      10,
      15,
      25,
      30,
      20,
      35,
      50,
      45,
      60,
      55,
      40,
      30,
      25,
      18,
      12,
      8
    ];
    final n = heights.length;
    final range = sliderMax - sliderMin;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(n, (i) {
          final price = sliderMin + (i / (n - 1)) * range;
          final inRange = price >= minBudget && price <= maxBudget;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              height: heights[i].toDouble(),
              decoration: BoxDecoration(
                color: inRange ? AppColors.primary : AppColors.border,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _PriceInputCard extends StatelessWidget {
  const _PriceInputCard({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleSelectorButton extends StatelessWidget {
  _CircleSelectorButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.24),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.navy,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _PropertyTypeCard extends StatelessWidget {
  _PropertyTypeCard({
    required this.label,
    required this.state,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final FilterPriority state;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isPreferred = state == FilterPriority.preferred;
    final bool isRequired = state == FilterPriority.required;
    final bool isActive = isPreferred || isRequired;

    final Color bgColor = isRequired
        ? AppColors.primary
        : (isPreferred ? AppColors.navy : AppColors.slate50);
    final Color iconBgColor =
        isActive ? Colors.white24 : AppColors.border;
    final Color labelColor = isActive ? Colors.white : AppColors.navy;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 108,
        height: 108,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isActive ? bgColor : AppColors.border,
            width: 1.5,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: bgColor.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: labelColor,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: labelColor,
                  ),
                ),
              ],
            ),
            if (isActive)
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: isRequired ? AppColors.coral : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isRequired
                          ? AppColors.coral
                          : Colors.white.withValues(alpha: 0.6),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    isRequired
                        ? Icons.priority_high_rounded
                        : Icons.check_rounded,
                    size: 12,
                    color: isRequired ? Colors.white : AppColors.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FeatureTag extends StatelessWidget {
  _FeatureTag({
    required this.label,
    required this.state,
    required this.onClear,
  });

  final String label;
  final FilterPriority state;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final bool isRequired = state == FilterPriority.required;
    final Color accent = isRequired ? AppColors.coral : AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.30), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRequired ? Icons.priority_high_rounded : Icons.favorite_rounded,
            size: 11,
            color: accent,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(width: 5),
          GestureDetector(
            onTap: onClear,
            child: Icon(
              Icons.close,
              size: 13,
              color: accent.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact price for a map pin: rentals as "₪5,400", sales as "₪2.0M".
String _pinPriceLabel(RentalProperty p) {
  final v = p.price;
  if (v >= 100000) {
    final m = v / 1000000;
    return '₪${m.toStringAsFixed(v % 1000000 == 0 ? 0 : 1)}M';
  }
  final s = v.toString();
  final b = StringBuffer('₪');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PillSelector extends StatefulWidget {
  _PillSelector({
    required this.selectedTab,
    required this.onTabChanged,
    required this.onMapTap,
  });

  final DiscoverTab selectedTab;
  final ValueChanged<DiscoverTab> onTabChanged;
  final VoidCallback onMapTap;

  @override
  State<_PillSelector> createState() => _PillSelectorState();
}

class _PillSelectorState extends State<_PillSelector> {
  // Variable widths so "במיוחד בשבילך" gets the room it needs, while "גלה" (short)
  // and the map icon stay compact. The sliding thumb resizes to the selected tab.
  static const _wForYou = 2.0;
  static const _wDiscover = 1.12;
  static const _wMap = 0.58;

  DiscoverTab? _pressedTab;
  bool _mapPressed = false;

  void _selectTab(DiscoverTab tab) {
    if (widget.selectedTab == tab) {
      HapticFeedback.selectionClick();
      return;
    }
    HapticFeedback.lightImpact();
    widget.onTabChanged(tab);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = MediaQuery.sizeOf(context).width - 124;
        final maxWidth =
            constraints.hasBoundedWidth ? constraints.maxWidth : fallbackWidth;
        final width = math.max(0.0, math.min(340.0, maxWidth));
        const pad = 5.0;
        final inner = math.max(0.0, width - pad * 2);
        final unit = inner / (_wForYou + _wDiscover + _wMap);
        final mapW = _wMap * unit;
        final discW = _wDiscover * unit;
        final forW = _wForYou * unit;
        // Visual order left→right: [map, גלה, במיוחד בשבילך].
        final isDiscover = widget.selectedTab == DiscoverTab.discover;
        final thumbLeft = isDiscover ? mapW : (mapW + discW);
        final thumbW = isDiscover ? discW : forW;

        return Semantics(
          label: AppLocalizations.of(context)!.discoverScreenFcde3740,
          child: SizedBox(
            width: width,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.96),
                    AppColors.primaryLight2.withValues(alpha: 0.94),
                    AppColors.slate50.withValues(alpha: 0.98),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.78),
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navy.withValues(alpha: 0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    blurRadius: 18,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(14), sigmaY: PlatformFx.blurSigma(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(pad),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      // Clip the sliding thumb's glow to the pill. An ancestor
                      // ClipRRect over a BackdropFilter does NOT contain child
                      // shadows on Android/Impeller, so the thumb glow leaked
                      // outside the component; clipping the Stack itself fixes it
                      // on both platforms (parent ClipRRect still rounds it).
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            left: thumbLeft,
                            width: thumbW,
                            top: 0,
                            bottom: 0,
                            child: _SlidingSelectorThumb(
                              energy: 0,
                              isDiscoverSelected: isDiscover,
                            ),
                          ),
                          Row(
                            children: [
                              SizedBox(width: mapW, child: _mapSegment()),
                              SizedBox(
                                width: discW,
                                child: _segment(
                                  tab: DiscoverTab.discover,
                                  icon: IconsaxPlusLinear.gallery,
                                  label: AppLocalizations.of(context)!
                                      .discoverScreenEed2fbf3,
                                  isSelected: isDiscover,
                                ),
                              ),
                              SizedBox(
                                width: forW,
                                child: _segment(
                                  tab: DiscoverTab.forYou,
                                  icon: IconsaxPlusBold.flash,
                                  label: AppLocalizations.of(context)!
                                      .discoverScreen2d073fb0,
                                  isSelected: !isDiscover,
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
            ),
          ),
        );
      },
    );
  }

  Widget _segment({
    required DiscoverTab tab,
    required IconData icon,
    required String label,
    required bool isSelected,
  }) {
    final inactiveColor = AppColors.textSecondary.withValues(alpha: 0.84);
    final pressed = _pressedTab == tab;
    final selectedShadow = [
      Shadow(
        color: AppColors.navy.withValues(alpha: 0.22),
        offset: const Offset(0, 1),
        blurRadius: 5,
      ),
    ];
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressedTab = tab),
        onTapUp: (_) => setState(() => _pressedTab = null),
        onTapCancel: () => setState(() => _pressedTab = null),
        onTap: () => _selectTab(tab),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          scale: pressed ? 0.93 : (isSelected ? 1.03 : 1),
          child: Padding(
            // Inset so the icon+text always stay INSIDE the coloured thumb — the
            // selected scale + the wider Android Hebrew rendering otherwise
            // spilled them past the thumb's edges ("יוצא מהקומפוננטה הצבעונית").
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedScale(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutBack,
                      scale: isSelected ? 1.14 : 1,
                      child: Icon(
                        icon,
                        size: 16,
                        color: isSelected ? Colors.white : inactiveColor,
                        shadows: isSelected ? selectedShadow : null,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1,
                        fontWeight:
                            isSelected ? FontWeight.w900 : FontWeight.w800,
                        color: isSelected ? Colors.white : inactiveColor,
                        shadows: isSelected ? selectedShadow : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Map + lasso — a selectable-looking icon segment that opens the area screen.
  Widget _mapSegment() {
    final inactiveColor = AppColors.textSecondary.withValues(alpha: 0.84);
    return Semantics(
      button: true,
      label: AppLocalizations.of(context)!.discoverScreen876e3baa,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _mapPressed = true),
        onTapUp: (_) => setState(() => _mapPressed = false),
        onTapCancel: () => setState(() => _mapPressed = false),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onMapTap();
        },
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          scale: _mapPressed ? 0.9 : 1,
          child: Center(
            child: Icon(IconsaxPlusLinear.map_1, size: 20, color: inactiveColor),
          ),
        ),
      ),
    );
  }
}

class _SlidingSelectorThumb extends StatelessWidget {
  _SlidingSelectorThumb({
    required this.energy,
    required this.isDiscoverSelected,
  });

  final double energy;
  final bool isDiscoverSelected;

  @override
  Widget build(BuildContext context) {
    final accent = isDiscoverSelected
        ? const Color(0xFF2F80ED)
        : AppColors.coral;
    final glowColor = isDiscoverSelected ? AppColors.superLike : AppColors.coral;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryLight, // was a fixed cyan bookend that ignored the theme
            AppColors.primary,
            accent,
          ],
          stops: const [0, 0.52, 1],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.30),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35 + energy * 0.18),
            blurRadius: 13 + energy * 10,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: glowColor.withValues(alpha: 0.18 + energy * 0.12),
            blurRadius: 20 + energy * 12,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(23),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.30),
                    Colors.white.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.07),
                  ],
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 6,
            start: 12,
            width: 38,
            height: 14,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.48),
                    Colors.white.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Curated nearby-place categories offered in the search filter (short labels +
/// the same icons the property card uses). The seeker's picks are surfaced first
/// on the property page AND boost the matching ranking dimensions.
List<(NearbyKind, String, IconData)> _nearbyPrefOptions(
    BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return [
    (NearbyKind.schools, l10n.discoverScreenFa8c72dc, IconsaxPlusLinear.teacher),
    (NearbyKind.kindergartens, l10n.discoverScreenBabfce71,
        IconsaxPlusLinear.emoji_happy),
    (NearbyKind.playgrounds, l10n.discoverScreen36bca392,
        IconsaxPlusLinear.game),
    (NearbyKind.parks, l10n.discoverScreen387c3b70, IconsaxPlusLinear.tree),
    (NearbyKind.supermarkets, l10n.discoverScreenD2d5595e,
        IconsaxPlusLinear.shopping_cart),
    (NearbyKind.clinics, l10n.discoverScreen88915bc2,
        IconsaxPlusLinear.hospital),
    (NearbyKind.pharmacies, l10n.discoverScreen82e78f66,
        IconsaxPlusLinear.health),
    (NearbyKind.hospitals, l10n.discoverScreenFeb803ce, IconsaxPlusLinear.heart),
    (NearbyKind.transit, l10n.discoverScreen91db7436, IconsaxPlusLinear.bus),
    (NearbyKind.gyms, l10n.discoverScreen83339279, IconsaxPlusLinear.weight),
    (NearbyKind.pools, l10n.discoverScreenAa390576, IconsaxPlusLinear.drop),
    (NearbyKind.dining, l10n.discoverScreenB86d6f75,
        IconsaxPlusLinear.reserve),
    (NearbyKind.nightlife, l10n.discoverScreenCc34e5d3, IconsaxPlusLinear.cup),
    (NearbyKind.culture, l10n.discoverScreen6432de42,
        IconsaxPlusLinear.gallery),
    (NearbyKind.synagogues, l10n.discoverScreenF93de50d,
        IconsaxPlusLinear.buildings),
    (NearbyKind.dogParks, l10n.discoverScreen56619b6e, IconsaxPlusLinear.pet),
    (NearbyKind.coworking, l10n.discoverScreen49d8274a,
        IconsaxPlusLinear.briefcase),
    (NearbyKind.parking, l10n.discoverScreenA6b678a2, IconsaxPlusLinear.car),
  ];
}

/// A binary (important / not) selectable chip for a nearby-place category.
class _NearbyKindChip extends StatelessWidget {
  const _NearbyKindChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? accent : AppColors.borderLight,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? accent : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? accent : AppColors.textPrimary,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 4),
              Icon(Icons.check_rounded, size: 15, color: accent),
            ],
          ],
        ),
      ),
    );
  }
}
