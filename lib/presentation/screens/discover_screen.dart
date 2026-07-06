import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/services/assistant_service.dart';
import 'package:dating_app/core/services/event_service.dart';
import 'package:dating_app/core/services/notification_service.dart';
import 'package:dating_app/core/services/aws_client.dart';
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
import 'package:dating_app/presentation/widgets/safe_media.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSavedSearches());
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(milliseconds: 2600),
        content: Text('לא הצלחתי להבין את החיפוש. נסו למשל: "3 חדרים בתל אביב עד 6000"'),
      ));
      return;
    }

    // 3) Map the NL query onto the live filters → discover deck re-ranks.
    final next = _filtersFromQuery(provider.filters, query);
    await provider.updateFilters(next);

    if (!mounted) return;
    setState(() {
      _nlBusy = false;
      _nlSummary = query.describe();
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

  /// Wraps [DatingProvider.handlePropertySwipe] to emit dwell + comparison-set
  /// signals at the decision moment, then delegates unchanged.
  Future<bool> _onSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) async {
    try {
      final props = context.read<DatingProvider>().filteredProperties;
      if (previousIndex >= 0 && previousIndex < props.length) {
        final decided = props[previousIndex];
        final dwellMs =
            DateTime.now().difference(_topCardShownAt).inMilliseconds;
        AppEvents.instance.service
            .logCardDwell(propertyId: decided.id, dwellMs: dwellMs);

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

    // Delegate to the (untouched) outcome handler in the provider.
    return context.read<DatingProvider>().handlePropertySwipe(
          previousIndex,
          currentIndex,
          direction,
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
    );
  }


  Widget _buildDiscoverGrid(
    List<RentalProperty> properties,
    DatingProvider provider,
  ) {
    if (properties.isEmpty) {
      return const _NoMorePropertiesState();
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
        final isGuest = provider.isGuestMode;
        final isFirst = isGuest && index == 0;
        final isSecond = isGuest && index == 1;
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PropertyDetailScreen(property: p),
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
                          label: '${p.roomsLabel} חד׳',
                        ),
                        _GlassPillBadge(
                          icon: IconsaxPlusLinear.maximize_3,
                          label: '${p.sizeM2} מ״ר',
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
                        if (isFirst) ...[
                          Row(
                            children: [
                              _GlassPillBadge(
                                icon: IconsaxPlusLinear.eye,
                                label: '245',
                              ),
                              const SizedBox(width: 4),
                              _GlassPillBadge(
                                icon: IconsaxPlusLinear.heart,
                                label: '84',
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ] else if (isSecond) ...[
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFFEF4444).withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: const Color(0xFFEF4444)
                                          .withOpacity(0.4),
                                      width: 0.8),
                                ),
                                child: const Text(
                                  'חדש!',
                                  style: TextStyle(
                                    color: Color(0xFFFCA5A5),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              _GlassPillBadge(
                                icon: IconsaxPlusLinear.heart,
                                label: '47',
                              ),
                              const SizedBox(width: 4),
                              _GlassPillBadge(
                                icon: IconsaxPlusLinear.people,
                                label: '3',
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ],
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
                                          key: ValueKey(
                                            provider.filteredPropertiesRevision,
                                          ),
                                          controller:
                                              provider.propertySwiperController,
                                          cardsCount: properties.length,
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
                                              math.min(3, properties.length),
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
                                                index >= properties.length) {
                                              return const SizedBox.shrink();
                                            }
                                            return Stack(
                                              children: [
                                                ProfileCard(
                                                  key: ValueKey(
                                                    properties[index].id,
                                                  ),
                                                  property: properties[index],
                                                  horizontalOffsetPercentage:
                                                      horizontalOffsetPercentage,
                                                ),
                                                FomoCardOverlay(
                                                  property: properties[index],
                                                  likedIds: provider.likedPropertyIds,
                                                ),
                                              ],
                                            );
                                          },
                                        )
                                      : const _NoMorePropertiesState(),
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

                                // Floating Undo button independently positioned on the bottom-left corner
                                if (properties.isNotEmpty && provider.canUndo)
                                  Positioned(
                                    bottom: 133,
                                    left: 24,
                                    child: Tooltip(
                                      message: 'חזור לפריט הקודם',
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
                                              color: const Color(0xFFE2E8F0),
                                              width: 1.5,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFFF59E0B)
                                                    .withOpacity(0.12),
                                                blurRadius: 12,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.rotate_left_rounded,
                                            color: Color(0xFFF59E0B),
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
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (!provider.isLandlord)
                      const _HeaderMenuButton()
                    else
                      const SizedBox(width: 42),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: _buildPillSelector(),
                      ),
                    ),
                    const SizedBox(width: 10),
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
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFiltersButton(BuildContext context, DatingProvider provider) {
    return GestureDetector(
      onTap: provider.isLoading
          ? null
          : () => _showFilters(context, provider),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFE2E8F0),
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
  const MatchCelebrationOverlay({super.key, required this.property});
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
      duration: const Duration(milliseconds: 1400),
    );
    _scale = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.65, curve: Curves.elasticOut),
    );
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.18), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.18, end: 1.0), weight: 55),
    ]).animate(CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.65, 1.0, curve: Curves.easeInOut),
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
    final media = p.primaryMedia;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Glassmorphism background blur
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                color: Colors.black.withOpacity(0.76),
              ),
            ),
          ),

          // Radial celebration glow
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.0,
                  colors: [
                    AppColors.primary.withOpacity(0.24),
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
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: _scale,
                    child: Column(
                      children: [
                        // Animated heartbeat container
                        ScaleTransition(
                          scale: _heartScale,
                          child: Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primary,
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.35),
                                  blurRadius: 24,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Center(
                              child: RentlyIcon(
                                IconsaxPlusBold.heart,
                                color: AppColors.primary,
                                size: 52,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'זה מאצ׳!',
                          style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -1.5,
                            shadows: [
                              Shadow(
                                color: Colors.black38,
                                offset: Offset(0, 3),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'נוצרה התאמה עם\n${p.address}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Polaroid-style tilted property image card
                  if (media != null)
                    ScaleTransition(
                      scale: _scale,
                      child: Transform.rotate(
                        angle: -0.04, // slight rotation for stylish look
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: SizedBox(
                              width: 240,
                              height: 160,
                              child: _MatchPropertyImage(media: media),
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 44),

                  // Custom Action Buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      children: [
                        // Open Chat Gradient Button
                        Container(
                          width: double.infinity,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              colors: [AppColors.primary, Color(0xFF5AD4DC)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const RentlyIcon(
                              IconsaxPlusLinear.message,
                              color: Colors.white,
                              size: 18,
                            ),
                            label: const Text(
                              'פתח צ׳אט',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Keep Searching text/glass button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text(
                              'המשך לחפש',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white70,
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
        ],
      ),
    );
  }
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

class _GlassPillBadge extends StatelessWidget {
  const _GlassPillBadge({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.12),
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
        ),
      ),
    );
  }
}

/// Natural-language search that lives on the right of the discover header as a
/// fully-rounded pill. Collapsed it's a 52px circle with a search icon; tapping
/// it animates (~1s) into the full-width search bar — the circle elongates and
/// widens leftward until it reaches full size. Closing reverses the same way.
class _AnimatedNlSearch extends StatefulWidget {
  const _AnimatedNlSearch({
    required this.open,
    required this.controller,
    required this.busy,
    required this.summary,
    required this.onOpen,
    required this.onClose,
    required this.onSubmit,
    required this.onClear,
  });

  final bool open;
  final TextEditingController controller;
  final bool busy;
  final String? summary;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;

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
                  // Min height keeps the collapsed circle; grows for multi-line text.
                  constraints: BoxConstraints(minHeight: _h),
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
              textDirection: TextDirection.rtl,
              // Multi-line: Enter inserts a line-break; the arrow button searches.
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 1,
              maxLines: 4,
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
                hintText: 'חפש דירה במילים שלך…',
                hintTextDirection: TextDirection.rtl,
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
            tooltip: hasContent ? 'נקה' : 'סגור',
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
        'נסו: "3 חדרים בצפון ת״א עד 6000"',
        textDirection: TextDirection.rtl,
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
              textDirection: TextDirection.rtl,
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
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: PopupMenuButton<int>(
            tooltip: 'עוד',
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
                    label: 'התראות',
                    badge: _unread),
              ),
              const PopupMenuItem(
                value: 1,
                child: _HeaderMenuRow(
                    icon: Icons.bookmark_border_rounded,
                    label: 'חיפושים שמורים'),
              ),
              const PopupMenuItem(
                value: 2,
                child: _HeaderMenuRow(
                    icon: Icons.favorite_border_rounded,
                    label: 'הדירות ששמרתי'),
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
  const _HeaderMenuRow(
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
  const _SaveSearchButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'שמור חיפוש',
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
              Text(
                'שמור',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
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
  const _FiltersSheet({required this.provider});
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
        ? 'אין מחיר'
        : _compactPriceLabel(averagePrice.round());
    return '$count דירות · $price';
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
              hintText: 'הכנס מספר',
            ),
            onSubmitted: (submitted) =>
                Navigator.of(dialogContext).pop(submitted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('שמור'),
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
                decoration: decoration('מינימום'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maxController,
                keyboardType: keyboardType,
                textAlign: TextAlign.right,
                decoration: decoration('מקסימום'),
                onSubmitted: (_) => Navigator.of(dialogContext).pop(
                  (minController.text, maxController.text),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                (minController.text, maxController.text),
              ),
              child: const Text('שמור'),
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
    final nameCtrl = TextEditingController(
      text: f.city.trim().isNotEmpty ? 'דירות ב${f.city.trim()}' : 'החיפוש שלי',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'שמירת חיפוש',
            style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'נשמור את הסינון הנוכחי ונודיע לך כשתעלה דירה חדשה שמתאימה.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(hintText: 'שם לחיפוש'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(nameCtrl.text),
              child: const Text('שמור'),
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      duration: Duration(milliseconds: 2500),
      content: Text('החיפוש נשמר. נודיע לך על דירות חדשות שמתאימות 🔔'),
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
            (city) => _LocationSuggestion.city(city),
          ),
          ...filteredAreas.map(
            (searchArea) => _LocationSuggestion.area(searchArea),
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
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF2F4F5),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close,
                                  size: 18, color: AppColors.navy),
                            ),
                          ),
                        ),
                        const Text(
                          'סינון ומיון',
                          style: TextStyle(
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
                          title: 'מטרה',
                          icon: IconsaxPlusLinear.category,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _TransactionCard(
                              label: 'הכל',
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
                              label: 'שכירות',
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
                              label: 'קנייה',
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
                          title: 'טווח מחירים',
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
                            inactiveTrackColor: const Color(0xFFE2ECF1),
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
                              label: 'מינימום',
                              value: _formatCurrency(f.minBudget.round()),
                              onTap: () => _editRangeValues(
                                context: context,
                                title: _priceFilterLabel(),
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
                              label: 'מקסימום',
                              value: f.maxBudget >= 2000000000
                                  ? 'ללא הגבלה'
                                  : _formatCurrency(f.maxBudget.round()),
                              onTap: () => _editRangeValues(
                                context: context,
                                title: _priceFilterLabel(),
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
                          title: const Text(
                            'לכלול דירות בלי מחיר',
                            style: TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: const Text(
                            'מחיר מתחת ל-600 ש"ח נחשב כלא ידוע',
                            style: TextStyle(
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
                          title: 'חדרים',
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
                                          : const Color(0xFFE2ECF1),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(
                                      color: f.minRooms > 0
                                          ? AppColors.primary
                                          : const Color(0xFFE2ECF1),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                                  ),
                                  hintText: 'מ-',
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
                                          : const Color(0xFFE2ECF1),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(
                                      color: f.maxRooms < 10
                                          ? AppColors.primary
                                          : const Color(0xFFE2ECF1),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                                  ),
                                  hintText: 'עד',
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
                          title: 'מיקום',
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
                                  child: const Text('הכל'),
                                )
                              : null,
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFE2ECF1)),
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
                                  textDirection: TextDirection.rtl,
                                  onChanged: (v) => setState(() {}),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.navy,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'חפש עיר או אזור',
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
                                  color: Color(0xFFF2F4F5),
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
                              textDirection: TextDirection.rtl,
                              children: [
                                for (final city in [
                                  'תל אביב',
                                  'ירושלים',
                                  'חיפה',
                                  'גבעתיים',
                                  'רמת גן',
                                  'הרצליה',
                                  'ראשון לציון',
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
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              'לא נמצאו ערים או אזורים מתאימים',
                              style: TextStyle(
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
                        const SizedBox(height: 14),
                        // Mini map
                        Container(
                          height: 160,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
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
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Stack(
                              children: [
                                FlutterMap(
                                  key: ValueKey(
                                    '${f.areaId}-${f.city}-${f.customAreaPolygon.length}',
                                  ),
                                  options: MapOptions(
                                    initialCenter: area.center,
                                    initialZoom:
                                        area.id == 'all_israel' ? 7.5 : 11,
                                    interactionOptions:
                                        const InteractionOptions(
                                      flags: InteractiveFlag.all,
                                    ),
                                    onTap: (_, __) async {
                                      final polygon =
                                          await Navigator.of(context)
                                              .push<List<LatLng>>(
                                        MaterialPageRoute(
                                          fullscreenDialog: true,
                                          builder: (_) => _AreaLassoScreen(
                                            initialArea: area,
                                            initialPolygon: f.customAreaPolygon,
                                            previewMarkers: _markerPreview,
                                            filters: _draftFilters,
                                          ),
                                        ),
                                      );
                                      if (!mounted || polygon == null) return;
                                      _setDraftFilters(
                                        f.copyWith(
                                          city: '',
                                          areaId: 'all_israel',
                                          customAreaPolygon: polygon,
                                        ),
                                        provider,
                                      );
                                    },
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate:
                                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName: 'com.rentch.app',
                                    ),
                                    PolygonLayer(
                                      polygons: [
                                        Polygon(
                                          points: area.polygon,
                                          color: AppColors.primary
                                              .withValues(alpha: 0.2),
                                          borderColor: AppColors.primary,
                                          borderStrokeWidth: 3,
                                        ),
                                      ],
                                    ),
                                    MarkerLayer(
                                      markers: _markerPreview
                                          .map((p) => Marker(
                                                point: p.point,
                                                width: 28,
                                                height: 28,
                                                child: RentlyIcon(
                                                    IconsaxPlusLinear.building,
                                                    color: AppColors.primary,
                                                    size: 22),
                                              ))
                                          .toList(),
                                    ),
                                  ],
                                ),
                                // Interactive overlay hint
                                Positioned(
                                  top: 12,
                                  right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.1),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.edit_location_alt_rounded,
                                          size: 14,
                                          color: AppColors.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          f.hasCustomArea
                                              ? 'ערוך אזור'
                                              : 'סמן אזור',
                                          style: const TextStyle(
                                            color: AppColors.navy,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
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
                        const SizedBox(height: 8),
                        Text(
                          f.hasCustomArea
                              ? 'האזור מסומן ידנית. אפשר להזיז את המפה וללחוץ עליה כדי לערוך את הלאסו.'
                              : 'אפשר להזיז את המפה. לחיצה עליה תפתח סימון ידני עם לאסו.',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // ── מיון ──
                        _FilterSection(
                            title: 'מיון', icon: IconsaxPlusLinear.sort),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: Row(
                            textDirection: TextDirection.rtl,
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
                                          _sortLabel(option),
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
                          label: 'טווח גודל',
                          icon: IconsaxPlusLinear.maximize_4,
                          values: RangeValues(
                            f.minSizeM2.toDouble().clamp(0, 2000),
                            f.maxSizeM2.toDouble().clamp(0, 2000),
                          ),
                          min: 0,
                          max: 2000,
                          divisions: 200,
                          displayValue:
                              _sizeDisplayValue(f.minSizeM2, f.maxSizeM2),
                          onValueTap: () => _editRangeValues(
                            context: context,
                            title: 'טווח גודל',
                            initialMinValue: f.minSizeM2.toString(),
                            initialMaxValue: f.maxSizeM2 >= 1000000
                                ? ''
                                : f.maxSizeM2.toString(),
                            suffix: 'מ"ר',
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
                          label: 'קומה מינימלית',
                          icon: IconsaxPlusLinear.building,
                          value: f.minFloor.toDouble(),
                          min: 0,
                          max: 30,
                          divisions: 30,
                          displayValue: f.minFloor == 0
                              ? 'ללא הגבלה'
                              : 'קומה ${f.minFloor}+',
                          onValueTap: () => _editSliderValue(
                            context: context,
                            title: 'קומה מינימלית',
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
                          title: 'סוג נכס',
                          icon: IconsaxPlusLinear.building,
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: Row(
                            textDirection: TextDirection.rtl,
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
                          title: 'מצב הנכס',
                          icon: IconsaxPlusLinear.shield_tick,
                          action: const _PriorityLegend(),
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
                          title: 'מקור מודעה',
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
                              label: _listingSourceLabel(source),
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
                        const Text(
                          'ללא בחירה: יוצגו גם פרטיות וגם מתיווך',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // ── מועד כניסה ──
                        _FilterSection(
                          title: 'מועד כניסה',
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
                              label: _moveInLabel(option),
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
                        const Text(
                          'ללא בחירה: כל מועדי הכניסה רלוונטיים',
                          style: TextStyle(
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
                              title: 'מאפיינים חשובים',
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
                              label: feature,
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
                        top: BorderSide(color: Color(0xFFE2ECF1)),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (!provider.isLandlord) ...[
                          _SaveSearchButton(
                            onTap: () => _saveCurrentSearch(context),
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
                            child: const Text(
                              'נקה הכל',
                              style: TextStyle(
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
                                'הצג $_visibleCount דירות',
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
  const _FilterSection(
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
  const _PriorityLegend();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LegendChip(
          label: 'מועדף',
          color: AppColors.primary,
          icon: Icons.favorite_rounded,
        ),
        const SizedBox(width: 8),
        _LegendChip(
          label: 'חייב להיות',
          color: AppColors.coral,
          icon: Icons.priority_high_rounded,
        ),
        const SizedBox(width: 10),
        const Text(
          'טאפ / דאבל טאפ',
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
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
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.w700,
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
  const _PriorityFilterChip({
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
  const _SliderField({
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
                      Text(
                        displayValue,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
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
  const _RangeSliderField({
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
                      Text(
                        displayValue,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
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
  const _AreaLassoScreen({
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
    if (!_drawMode || _activePointers > 1) {
      if (_activePointers > 1) {
        setState(() {
          _currentPolygon.clear();
        });
      }
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
    setState(() => _lastDrawOffset = null);
  }

  void _cancelLasso(PointerCancelEvent event) {
    _activePointers = math.max(0, _activePointers - 1);
    setState(() => _lastDrawOffset = null);
  }

  void _locateUser() {
    if (_markers.isNotEmpty) {
      _animatedMapMove(_markers.first.point, 13.5);
    } else {
      _animatedMapMove(widget.initialArea.center, 12.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Recompute the visible properties from the live catalogue → a property a
    // landlord just uploaded (or any catalogue refresh) shows up immediately.
    _markers = context
        .watch<DatingProvider>()
        .previewFilteredProperties(widget.filters);
    final polygon = _activePolygon;
    final canSave = polygon.length >= 3;
    final hasProperties = _markers.isNotEmpty;
    final hasPolygon = polygon.length >= 3;

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
                markers: _markers.map(
                  (property) {
                    final isSelected = property.id == _selectedProperty?.id;
                    return Marker(
                      point: property.point,
                      width: isSelected ? 66 : 46,
                      height: isSelected ? 74 : 54,
                      child: GestureDetector(
                        onTap: () => _selectProperty(property),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: isSelected ? 60 : 40,
                              height: isSelected ? 60 : 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF2C64E3)
                                      : Colors.white,
                                  width: isSelected ? 3.0 : 2.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.16),
                                    blurRadius: isSelected ? 8 : 4,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: SafeMedia(
                                  media: property.primaryMedia,
                                  fallback: Container(
                                    color: AppColors.primaryLight2,
                                    child: RentlyIcon(
                                      IconsaxPlusLinear.building,
                                      size: isSelected ? 22 : 14,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            if (isSelected)
                              CustomPaint(
                                size: const Size(10, 6),
                                painter: _TrianglePainter(
                                    color: const Color(0xFF2C64E3)),
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
                    border: Border.all(color: const Color(0xFFE2ECF1)),
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
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                // Filter Dropdown Button replacing Search Bar
                Expanded(
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      cardColor: Colors.white,
                    ),
                    child: PopupMenuButton<String>(
                      tooltip: 'סוגי סינון',
                      onSelected: (value) {
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
                      offset: const Offset(0, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: Color(0xFFE2ECF1)),
                      ),
                      itemBuilder: (BuildContext context) => [
                        const PopupMenuItem<String>(
                          value: 'price',
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('תקציב',
                                  style: TextStyle(
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5)),
                              SizedBox(width: 8),
                              Icon(Icons.monetization_on_outlined,
                                  color: AppColors.navy, size: 18),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'rooms',
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('חדרים',
                                  style: TextStyle(
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5)),
                              SizedBox(width: 8),
                              Icon(Icons.meeting_room_outlined,
                                  color: AppColors.navy, size: 18),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'type',
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('סוג נכס',
                                  style: TextStyle(
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5)),
                              SizedBox(width: 8),
                              Icon(Icons.home_work_outlined,
                                  color: AppColors.navy, size: 18),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'features',
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('מאפיינים',
                                  style: TextStyle(
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5)),
                              SizedBox(width: 8),
                              Icon(Icons.star_border_rounded,
                                  color: AppColors.navy, size: 18),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem<String>(
                          value: 'all',
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('הצג את כל המסננים',
                                  style: TextStyle(
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13.5)),
                              SizedBox(width: 8),
                              Icon(Icons.tune_rounded,
                                  color: AppColors.navy, size: 18),
                            ],
                          ),
                        ),
                      ],
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: const Color(0xFFE2ECF1)),
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
                                    ? 'סנן לפי...'
                                    : 'סינון באזור ${widget.initialArea.name}',
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
                ),
                const SizedBox(width: 8),
                // Locate User Button
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE2ECF1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.gps_fixed_rounded,
                        color: AppColors.navy),
                    onPressed: _locateUser,
                  ),
                ),
                const SizedBox(width: 8),
                // Lasso toggle Button
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _drawMode ? AppColors.primary : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(
                      _drawMode
                          ? Icons.gesture_rounded
                          : Icons.gesture_outlined,
                      color: _drawMode ? Colors.white : AppColors.navy,
                    ),
                    onPressed: () {
                      setState(() {
                        _drawMode = !_drawMode;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          // Bottom Area: Floating Card and Save buttons
          // 1. Bottom Headers: Styled as premium tags/chips with liquid glass
          if (hasProperties)
            Positioned(
              left: 16,
              right: 16,
              bottom: 368 + MediaQuery.of(context).padding.bottom,
              child: GestureDetector(
                onTap: canSave
                    ? () =>
                        Navigator.of(context).pop(List<LatLng>.from(polygon))
                    : null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.38),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: const Text(
                            'דירות באזור המסומן',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.26),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Text(
                            '${_markers.length} תוצאות',
                            style: const TextStyle(
                              color: Colors.white, // Solid white text
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
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
                                        property: property),
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

          // 3. Action buttons (Clear & Save) positioned at the bottom
          Positioned(
            left: 16,
            right: 16,
            bottom: 4 + MediaQuery.of(context).padding.bottom,
            child: Row(
              children: [
                // Clear Lasso Button (Liquid Glass)
                Expanded(
                  flex: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
                              _selectedProperty =
                                  _markers.firstOrNull;
                            });
                          },
                          icon: const Icon(Icons.refresh_rounded,
                              color: Colors.white, size: 18),
                          label: const Text(
                            'נקה',
                            style: TextStyle(
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
                // Save Lasso Button (Vibrant sky blue/cyan when canSave is true)
                Expanded(
                  flex: 2,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: canSave
                              ? const Color(0xFF38B6FF)
                                  .withValues(alpha: 0.85) // Sky Blue / Cyan
                              : Colors.black.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: canSave
                                ? const Color(0xFF38B6FF).withValues(alpha: 0.4)
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: TextButton.icon(
                          onPressed: canSave
                              ? () => Navigator.of(context)
                                  .pop(List<LatLng>.from(polygon))
                              : null,
                          icon: Icon(
                            Icons.check_circle_outline_rounded,
                            color: canSave
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.4),
                            size: 18,
                          ),
                          label: Text(
                            'שמור אזור',
                            style: TextStyle(
                              color: canSave
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.4),
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
  const _PropertyThumb({required this.media});

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
  const _PropertyPreviewCard({
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
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
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
                          Text(
                            isRent ? 'להשכרה' : 'למכירה',
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

              // Top-Right details open icon button
              Positioned(
                top: 12,
                right: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
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
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
                                label: '${property.roomsLabel} חדרים',
                              ),
                              _buildSpecPill(
                                icon: Icons.crop_free_rounded,
                                label: '${property.sizeM2} מ״ר',
                              ),
                              _buildSpecPill(
                                icon: Icons.layers_outlined,
                                label: property.floor.isEmpty
                                    ? 'קרקע'
                                    : 'קומה ${property.floor}',
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
          children: const [
            RentlyIcon(IconsaxPlusLinear.undo,
                size: 16, color: AppColors.textSecondary),
            SizedBox(width: 5),
            Text(
              'בטל',
              style: TextStyle(
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
  const _NoMorePropertiesState();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DatingProvider>();
    // Distinguish "you searched an area and there's nothing" (an OOPS empty state)
    // from "you swiped through everything" — the copy should match the situation.
    final city = provider.filters.city.trim();
    final hasActiveSearch = city.isNotEmpty ||
        provider.filters.minBudget != null ||
        provider.filters.maxBudget != 0 ||
        provider.filters.minRooms > 1;
    final title = hasActiveSearch
        ? (city.isNotEmpty ? 'אופס! לא מצאנו דירות ב$city' : 'אופס! אין דירות שמתאימות')
        : 'ראית את כל הדירות!';
    final subtitle = hasActiveSearch
        ? 'לא נמצאו דירות זמינות לפי החיפוש הזה. אפשר להרחיב טווח, אזור או תקציב 👇'
        : 'הרחב את החיפוש כדי למצוא עוד דירות';

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
              label: 'הרחב תקציב ב-₪500',
              onTap: () => provider.updateFilters(
                provider.filters.copyWith(
                  maxBudget: provider.filters.maxBudget + 500,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _QuickActionBtn(
              icon: IconsaxPlusLinear.home,
              label: 'הפחת דרישת חדרים ב-0.5',
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
              label: 'פתח גודל מ-20 מ"ר',
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
              label: 'אפס דירות שדילגתי',
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
  const _QuickActionBtn({
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
              const Color(0xFFE8EDF2),
              const Color(0xFFF4F6F9),
              _shimmer.value,
            )!;
            final highlight = Color.lerp(
              const Color(0xFFDDE3EB),
              const Color(0xFFEBEFF4),
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

String _sortLabel(SearchSortOption option) {
  switch (option) {
    case SearchSortOption.bestMatch:
      return 'התאמה חכמה';
    case SearchSortOption.priceLowToHigh:
      return 'מחיר מהנמוך לגבוה';
    case SearchSortOption.priceHighToLow:
      return 'מחיר מהגבוה לנמוך';
    case SearchSortOption.newestEntry:
      return 'כניסה הכי קרובה';
    case SearchSortOption.biggestFirst:
      return 'הכי מרווחות';
  }
}

String _listingSourceLabel(ListingSourceFilter source) {
  switch (source) {
    case ListingSourceFilter.any:
      return 'הכל';
    case ListingSourceFilter.privateOnly:
      return 'בעלים פרטיים';
    case ListingSourceFilter.agencyOnly:
      return 'תיווך בלבד';
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

  factory _LocationSuggestion.city(String city) {
    return _LocationSuggestion._(
      label: city,
      icon: IconsaxPlusLinear.building,
      caption: 'עיר',
      isCity: true,
    );
  }

  factory _LocationSuggestion.area(SearchArea area) {
    return _LocationSuggestion._(
      label: area.name,
      icon: IconsaxPlusLinear.location,
      caption: 'אזור',
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
  const _LocationSuggestionTile({
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

String _priceFilterLabel() => 'טווח מחיר';

/// Display label for the size range slider.
/// When maxSizeM2 is at or above the slider ceiling (2000) or "unlimited",
/// we show a "2,000+ מ"ר" label instead of the raw large number.
String _sizeDisplayValue(int minSizeM2, int maxSizeM2) {
  final minStr = minSizeM2 == 0 ? '0' : '$minSizeM2';
  if (maxSizeM2 >= 1000000) {
    return minSizeM2 == 0 ? 'ללא הגבלה' : '$minStr+ מ"ר';
  }
  if (maxSizeM2 >= 2000) {
    return '$minStr - 2,000+ מ"ר';
  }
  return '$minStr - $maxSizeM2 מ"ר';
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

String _moveInLabel(MoveInFilter option) {
  switch (option) {
    case MoveInFilter.any:
      return 'כל מועד';
    case MoveInFilter.immediate:
      return 'מיידי';
    case MoveInFilter.within30Days:
      return 'עד 30 יום';
    case MoveInFilter.within90Days:
      return 'עד 90 יום';
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
            color: isSelected ? AppColors.navy : const Color(0xFFE2ECF1),
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
  const _TransactionCard({
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
                        'חי',
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
  const _PriceHistogram({
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
                color: inRange ? AppColors.primary : const Color(0xFFE2ECF1),
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
            border: Border.all(color: const Color(0xFFE2ECF1)),
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
  const _CircleSelectorButton({
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
            color: isSelected ? AppColors.primary : const Color(0xFFE2ECF1),
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
  const _PropertyTypeCard({
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
        : (isPreferred ? AppColors.navy : const Color(0xFFF7F9FA));
    final Color iconBgColor =
        isActive ? Colors.white24 : const Color(0xFFE2ECF1);
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
            color: isActive ? bgColor : const Color(0xFFE2ECF1),
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
  const _FeatureTag({
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
  const _PillSelector({
    required this.selectedTab,
    required this.onTabChanged,
  });

  final DiscoverTab selectedTab;
  final ValueChanged<DiscoverTab> onTabChanged;

  @override
  State<_PillSelector> createState() => _PillSelectorState();
}

class _PillSelectorState extends State<_PillSelector>
    with SingleTickerProviderStateMixin {
  static const _selectorSpring = SpringDescription(
    mass: 0.72,
    stiffness: 520,
    damping: 30,
  );

  late final AnimationController _controller;
  bool _hasSyncedInitialPosition = false;

  bool _isDiscoverPressed = false;
  bool _isForYouPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(
      vsync: this,
      value: 0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final target = _targetFor(widget.selectedTab);
    if (!_hasSyncedInitialPosition) {
      _controller.value = target;
      _hasSyncedInitialPosition = true;
    } else if (!_controller.isAnimating) {
      _controller.value = target;
    }
  }

  @override
  void didUpdateWidget(covariant _PillSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTab != widget.selectedTab) {
      _springToSelected();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _targetFor(DiscoverTab tab) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    if (tab == DiscoverTab.discover) {
      return isRtl ? 1.0 : -1.0;
    }
    return isRtl ? -1.0 : 1.0;
  }

  void _springToSelected() {
    final target = _targetFor(widget.selectedTab);
    final delta = target - _controller.value;
    final kick = delta.sign * math.max(3.4, delta.abs() * 3.1);
    _controller.animateWith(
      SpringSimulation(
        _selectorSpring,
        _controller.value,
        target,
        kick,
      ),
    );
  }

  void _setPressed(DiscoverTab tab, bool isPressed) {
    setState(() {
      if (tab == DiscoverTab.discover) {
        _isDiscoverPressed = isPressed;
      } else {
        _isForYouPressed = isPressed;
      }
    });
  }

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
        final fallbackWidth = MediaQuery.sizeOf(context).width - 128;
        final maxWidth =
            constraints.hasBoundedWidth ? constraints.maxWidth : fallbackWidth;
        final width = math.max(0.0, math.min(306.0, maxWidth));

        return Semantics(
          label: 'בחירת תצוגת דירות',
          child: SizedBox(
            width: width,
            height: 52,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final alignmentX =
                    _controller.value.clamp(-1.08, 1.08).toDouble();
                final targetX = _targetFor(widget.selectedTab);
                final velocity =
                    (_controller.velocity.abs() / 14).clamp(0.0, 1.0).toDouble();
                final distance =
                    (targetX - _controller.value).abs().clamp(0.0, 1.0).toDouble();
                final energy = math.max(velocity, distance * 0.65);
                final stretch = 1.0 + energy * 0.22;
                final squeeze = 1.0 - energy * 0.08;
                final isDiscoverSelected =
                    widget.selectedTab == DiscoverTab.discover;

                return DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.96),
                        const Color(0xFFEAF9FB).withValues(alpha: 0.94),
                        const Color(0xFFF8FBFD).withValues(alpha: 0.98),
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
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _SelectorEnergyPainter(
                                  alignmentX: alignmentX,
                                  energy: energy,
                                  isDiscoverSelected: isDiscoverSelected,
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Align(
                                alignment: Alignment(alignmentX, 0),
                                child: FractionallySizedBox(
                                  widthFactor: 0.5,
                                  heightFactor: 1,
                                  child: Transform.scale(
                                    scaleX: stretch,
                                    scaleY: squeeze,
                                    child: _SlidingSelectorThumb(
                                      energy: energy,
                                      isDiscoverSelected: isDiscoverSelected,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                _buildSegment(
                                  tab: DiscoverTab.discover,
                                  icon: IconsaxPlusLinear.location,
                                  label: 'גלה',
                                  isSelected: isDiscoverSelected,
                                  isPressed: _isDiscoverPressed,
                                ),
                                _buildSegment(
                                  tab: DiscoverTab.forYou,
                                  icon: IconsaxPlusBold.flash,
                                  label: 'במיוחד בשבילך',
                                  isSelected: !isDiscoverSelected,
                                  isPressed: _isForYouPressed,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildSegment({
    required DiscoverTab tab,
    required IconData icon,
    required String label,
    required bool isSelected,
    required bool isPressed,
  }) {
    final inactiveColor = AppColors.textSecondary.withValues(alpha: 0.84);
    final selectedShadow = [
      Shadow(
        color: AppColors.navy.withValues(alpha: 0.22),
        offset: const Offset(0, 1),
        blurRadius: 5,
      ),
    ];

    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(tab, true),
          onTapUp: (_) => _setPressed(tab, false),
          onTapCancel: () => _setPressed(tab, false),
          onTap: () => _selectTab(tab),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            scale: isPressed ? 0.93 : (isSelected ? 1.03 : 1),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isPressed && !isSelected
                        ? AppColors.navy.withValues(alpha: 0.06)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedRotation(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutBack,
                        turns: isSelected && tab == DiscoverTab.forYou
                            ? -0.06
                            : 0,
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutBack,
                          scale: isSelected ? 1.16 : 1,
                          child: Icon(
                            icon,
                            size: 16,
                            color: isSelected ? Colors.white : inactiveColor,
                            shadows: isSelected ? selectedShadow : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOutCubic,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1,
                          letterSpacing: 0,
                          fontWeight:
                              isSelected ? FontWeight.w900 : FontWeight.w800,
                          color: isSelected ? Colors.white : inactiveColor,
                          shadows: isSelected ? selectedShadow : null,
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                        ),
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
  }
}

class _SlidingSelectorThumb extends StatelessWidget {
  const _SlidingSelectorThumb({
    required this.energy,
    required this.isDiscoverSelected,
  });

  final double energy;
  final bool isDiscoverSelected;

  @override
  Widget build(BuildContext context) {
    final accent = isDiscoverSelected
        ? const Color(0xFF2F80ED)
        : const Color(0xFFFF6B7A);
    final glowColor = isDiscoverSelected ? AppColors.superLike : AppColors.coral;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF14D3DC),
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

class _SelectorEnergyPainter extends CustomPainter {
  _SelectorEnergyPainter({
    required this.alignmentX,
    required this.energy,
    required this.isDiscoverSelected,
  });

  final double alignmentX;
  final double energy;
  final bool isDiscoverSelected;

  @override
  void paint(Canvas canvas, Size size) {
    final activeCenter = Offset(
      size.width * (0.25 + ((alignmentX + 1) / 2) * 0.5),
      size.height / 2,
    );
    final railPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.primary.withValues(alpha: 0.12 + energy * 0.08);
    final rail = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(24),
    ).deflate(0.5);
    canvas.drawRRect(rail, railPaint);

    final sparkPaint = Paint()..style = PaintingStyle.fill;
    final leadColor =
        isDiscoverSelected ? AppColors.superLike : AppColors.coral;
    final sparks = <({Offset offset, double radius, Color color})>[
      (
        offset: Offset(-size.width * 0.18, -size.height * 0.25),
        radius: 2.1 + energy * 1.4,
        color: leadColor,
      ),
      (
        offset: Offset(size.width * 0.18, size.height * 0.23),
        radius: 1.7 + energy * 1.1,
        color: AppColors.primary,
      ),
      (
        offset: Offset(size.width * 0.04, -size.height * 0.30),
        radius: 1.2 + energy * 0.9,
        color: Colors.white,
      ),
    ];

    for (final spark in sparks) {
      sparkPaint.color = spark.color.withValues(alpha: 0.20 + energy * 0.35);
      canvas.drawCircle(activeCenter + spark.offset, spark.radius, sparkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SelectorEnergyPainter oldDelegate) {
    return oldDelegate.alignmentX != alignmentX ||
        oldDelegate.energy != energy ||
        oldDelegate.isDiscoverSelected != isDiscoverSelected;
  }
}
