import 'dart:math' as math;

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/candidate_filters.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/data/repositories/property_likes_repository.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/features/discover/action_button.dart';
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
  const ExploreScreen({super.key, this.embedded = false, this.onGoToMessages});

  /// When true, the screen renders as a self-contained body inside a merged
  /// host (no AppBar, transparent background) so it can sit under a shared
  /// toggle. Everything else (deck, empty state, FABs) is unchanged.
  final bool embedded;

  /// When non-null, the "עבור לשיחות" empty-state button switches the merged
  /// host to its הודעות segment instead of pushing a chrome-less MatchesScreen
  /// (which has no back button and strands the user). Null → the standalone
  /// fallback push (NAV-B).
  final VoidCallback? onGoToMessages;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  int _currentIndex = 0;
  CandidateFilters _filters = CandidateFilters.empty;

  @override
  void initState() {
    super.initState();
    // Phase-0: pull the server's strong two-sided lead ranking (/match/leads)
    // so the deck orders + scores candidates by tags/deal-breakers/affordability,
    // not just the local budget/timing heuristic. Fail-soft — no-op off-network.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DatingProvider>().refreshRankedLeads();
    });
  }

  /// The representative liker for a property lead — the first tenant who liked
  /// it. The candidate deck is property-based, so it surfaces one liker per
  /// property; per-liker cards are a future enhancement. Returns null for demo
  /// leads that have no real incoming like yet.
  PropertyLike? _representativeLiker(
      DatingProvider provider, RentalProperty property) {
    // Phase-0: the BEST-fitting interested tenant (server score / budget fit),
    // not an arbitrary first — so the card + score describe the same candidate.
    return provider.bestLikerFor(property);
  }

  /// Builds the REAL, per-candidate attributes for a lead, sourced from the
  /// representative liker's snapshot. Every field is null (unknown → never
  /// excluded) when the liker didn't carry it.
  ///   * fitScore       — provider.leadFitScore (real, varies per property)
  ///   * availableInDays — from the liked property's entry date (real)
  ///   * budget          — the liker's snapshotted budgetMax (falls back to a
  ///                       parsed budgetSnapshot string for older likes)
  ///   * occupation/children/pets/car/wfh/household/income/verified — from the
  ///     liker's structured attribute snapshot
  CandidateAttributes _attributesFor(
      DatingProvider provider, RentalProperty property) {
    final entry = property.entryDateValue;
    final availableInDays = entry == null
        ? null
        : entry.difference(DateTime.now()).inDays.clamp(0, 3650);

    final liker = _representativeLiker(provider, property);
    final budget = liker?.budgetMax?.toDouble() ??
        _parseBudget(liker?.budgetSnapshot ?? '');

    final createdAt = liker?.createdAt;
    final likedInDays = createdAt == null
        ? null
        : DateTime.now().difference(createdAt).inDays.clamp(0, 36500);

    // Affordability: income ÷ this property's rent (null when either is missing
    // or the price is non-positive).
    final income = liker?.monthlyIncome;
    final incomeToRentRatio = (income != null && property.price > 0)
        ? income / property.price
        : null;

    // Commute: distance from the tenant's work location to this property, when
    // a work location was snapshotted with the like.
    final workLat = liker?.workLat;
    final workLon = liker?.workLon;
    final commuteKm = (workLat != null && workLon != null)
        ? _haversineKm(workLat, workLon, property.lat, property.lon)
        : null;

    return CandidateAttributes(
      fitScore: provider.leadFitScore(property),
      availableInDays: availableInDays,
      budget: budget,
      occupation: liker?.occupation,
      numChildren: liker?.numChildren,
      hasPets: liker?.hasPets,
      hasCar: liker?.hasCar,
      wfh: liker?.wfh,
      household: liker?.household,
      income: income?.toDouble(),
      verified: liker?.verified,
      age: liker?.age,
      lifeStage: liker?.lifeStage,
      rooms: liker?.rooms,
      likedInDays: likedInDays,
      incomeToRentRatio: incomeToRentRatio,
      isOleh: liker?.isOleh,
      commuteKm: commuteKm,
      smoker: liker?.smoker,
      hasGuarantor: liker?.hasGuarantor,
      leaseMonths: liker?.leaseMonths,
      incomeProofReady: liker?.incomeProofReady,
      religiousLifestyle: liker?.religiousLifestyle,
      shabbatObservant: liker?.shabbatObservant,
      keepsKosher: liker?.keepsKosher,
      petType: liker?.petType,
      hostsGuests: liker?.hostsGuests,
      playsInstrument: liker?.playsInstrument,
    );
  }

  /// Great-circle distance in km between two lat/lon points (Haversine).
  double _haversineKm(double la1, double lo1, double la2, double lo2) {
    const r = 6371.0;
    final dLat = (la2 - la1) * math.pi / 180.0;
    final dLon = (lo2 - lo1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1 * math.pi / 180.0) *
            math.cos(la2 * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Pulls a ₪ amount out of a free-form snapshot like "עד ₪6,500". Returns null
  /// when no number is present.
  double? _parseBudget(String snapshot) {
    if (snapshot.isEmpty) return null;
    final digits = snapshot.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return double.tryParse(digits);
  }

  List<RentalProperty> _applyFilters(
      DatingProvider provider, List<RentalProperty> leads) {
    if (_filters.isEmpty) return leads;
    return leads
        .where((p) => _filters.matches(_attributesFor(provider, p)))
        .toList();
  }

  Future<void> _openFilterSheet(DatingProvider provider) async {
    final result = await showModalBottomSheet<CandidateFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CandidateFilterSheet(initial: _filters),
    );
    if (result != null && mounted) {
      setState(() {
        _filters = result;
        _currentIndex = 0;
      });
    }
  }

  void _setFilters(CandidateFilters next) {
    setState(() {
      _filters = next;
      _currentIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final l10n = AppLocalizations.of(context)!;
        final currentProfile = provider.tenantProfile;
        // No FABRICATED person: when the viewer is a landlord, the card is driven
        // by the real interested tenant (the liker snapshot). This base carries
        // only a neutral generic label ("מועמד/ת") and NO fake bio/income/photo —
        // so a lead that lacks a real liker shows an honest generic candidate
        // instead of the old made-up "נועה לוי, ₪14,500".
        final tenant = provider.isLandlord
            ? TenantProfile(
                id: '',
                name: l10n.exploreScreen041446d3,
                bio: '',
                photoUrls: [],
                budgetMax: 0,
                desiredRooms: 0,
                moveInWindow: '',
                importantDetails: [],
              )
            : currentProfile;
        final allLeads = provider.ownerLeads;
        final leads = _applyFilters(provider, allLeads);
        final total = leads.length;

        // Reset index safely if total changes
        final safeIndex = total > 0 ? _currentIndex.clamp(0, total - 1) : 0;

        return Scaffold(
          backgroundColor:
              widget.embedded ? Colors.transparent : AppColors.background,
          appBar: widget.embedded
              ? null
              : AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: AppColors.background,
            elevation: 0,
            centerTitle: true,
            title: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.slate100,
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
                    l10n.exploreScreenEb3c6f60,
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
                  // When embedded in the merged לקוחות screen the host already
                  // applies the top inset above the segment toggle — re-applying
                  // it here would double the status-bar gap (NAV-A).
                  top: !widget.embedded,
                  bottom: false,
                  child: Column(
                    children: [
                      if (widget.embedded)
                        const SizedBox(height: 8.0),
                      // Thin, low-profile top bar: the single filters entry
                      // (icon + active-count badge) and a compact auto-like
                      // toggle — sits directly above the candidate deck.
                      _CandidateTopBar(
                        autoLikeEnabled: provider.autoLikeEnabled,
                        onToggleAutoLike: () {
                          HapticFeedback.mediumImpact();
                          provider.toggleAutoLike();
                        },
                        activeFilterCount: _filters.activeCount,
                        showFilters: allLeads.isNotEmpty,
                        onOpenFilters: () => _openFilterSheet(provider),
                      ),
                      Expanded(
                        child: allLeads.isEmpty
                            ? _EmptyOwnerQueue(
                                onGoToMessages: widget.onGoToMessages)
                            : leads.isEmpty
                                ? _NoMatchingCandidates(
                                    onClear: () =>
                                        _setFilters(CandidateFilters.empty),
                                  )
                                : Stack(
                                    children: [
                                      // Full-bleed deck mirroring the tenant
                                      // apartment-search deck: the CardSwiper
                                      // fills the whole deck area, so the card
                                      // reads at full size like ProfileCard —
                                      // not a short, boxed sheet.
                                      Positioned.fill(
                                        child: CardSwiper(
                                          key: ValueKey(leads
                                              .map((p) => p.id)
                                              .join('-')),
                                          controller:
                                              provider.ownerSwiperController,
                                          cardsCount: leads.length,
                                          // Same shape as discover: fill to the
                                          // edges, leaving only a small inset so
                                          // the floating action buttons overlay
                                          // the card's bottom gradient.
                                          // Embedded under the HomeScreen's glass
                                          // bottom nav (extendBody) → leave 130 at
                                          // the bottom so the card doesn't hide
                                          // under the bar (matches discover).
                                          padding: EdgeInsets.fromLTRB(
                                              10, 8, 10, widget.embedded ? 130 : 8),
                                          scale: 0.93,
                                          threshold: 38,
                                          maxAngle: 16,
                                          isLoop: false,
                                          numberOfCardsDisplayed:
                                              math.min(3, leads.length),
                                          backCardOffset: const Offset(0, 20),
                                          allowedSwipeDirection:
                                              const AllowedSwipeDirection.only(
                                            left: true,
                                            right: true,
                                            up: true,
                                          ),
                                          onSwipe: (prev, current, dir) {
                                            // The deck's ValueKey is derived
                                            // from the visible ids, so
                                            // accept/reject shrinks the list
                                            // and the CardSwiper resets to its
                                            // internal index 0 (top card).
                                            // Mirror that here — using [current]
                                            // would leave _currentIndex stale
                                            // and point the counter + ⓘ button at
                                            // the wrong candidate.
                                            if (mounted) {
                                              setState(() => _currentIndex = 0);
                                            }
                                            return provider.handleOwnerSwipe(
                                              prev,
                                              current,
                                              dir,
                                              visibleLeads: leads,
                                            );
                                          },
                                          cardBuilder: (context, index, hOffset,
                                              vOffset) {
                                            if (index < 0 ||
                                                index >= leads.length) {
                                              return const SizedBox.shrink();
                                            }
                                            final lead = leads[index];
                                            return _LeadCard(
                                              tenant: tenant,
                                              liker: _representativeLiker(
                                                  provider, lead),
                                              property: lead,
                                              reviews: provider.tenantReviews,
                                              hOffset: hOffset,
                                              isHighFit:
                                                  provider.isHighFitLead(lead),
                                              fitReason:
                                                  provider.leadFitReason(lead),
                                              fitScore:
                                                  provider.leadFitScore(lead),
                                              additionalInterested: provider
                                                  .additionalInterestedCount(
                                                      lead.id),
                                            );
                                          },
                                        ),
                                      ),

                                      // Floating swipe action buttons overlaying
                                      // the deck bottom — same placement discover
                                      // uses (reject / details / accept).
                                      Positioned(
                                        // Float above the glass bottom nav when
                                        // embedded (matches discover's bottom:140).
                                        bottom: widget.embedded ? 140 : 20,
                                        left: 0,
                                        right: 0,
                                        child: RepaintBoundary(
                                          // Exact same button set as the tenant
                                          // apartment-search deck (♥ / center / ✕),
                                          // with an "info" middle instead of 3D.
                                          child: ActionButtons(
                                            onSwipeRight:
                                                provider.ownerSwipeRight,
                                            onSwipeLeft: provider.ownerSwipeLeft,
                                            onVirtualTour: () {
                                              if (leads.isEmpty ||
                                                  safeIndex >= leads.length) {
                                                return;
                                              }
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      TenantDetailScreen(
                                                    tenant: tenant,
                                                    property: leads[safeIndex],
                                                    reviews:
                                                        provider.tenantReviews,
                                                  ),
                                                ),
                                              );
                                            },
                                            middleIcon:
                                                Icons.info_outline_rounded,
                                            middleLabel:
                                                l10n.exploreScreenA4ce69e7,
                                            middleTooltip:
                                                l10n.exploreScreen81a45c4e,
                                            likeTooltip:
                                                l10n.exploreScreenE702c2a5,
                                            passTooltip:
                                                l10n.exploreScreen80a413c5,
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
      },
    );
  }

  Color _trustColor(int score) {
    if (score >= 80) return AppColors.success;
    if (score >= 50) return AppColors.carrot;
    return AppColors.coral;
  }
}

// ─── Lead Card ────────────────────────────────────────────────────────────────

class _LeadCard extends StatefulWidget {
  _LeadCard({
    required this.tenant,
    required this.liker,
    required this.property,
    required this.reviews,
    required this.hOffset,
    required this.isHighFit,
    required this.fitReason,
    required this.fitScore,
    this.additionalInterested = 0,
  });

  /// The current user's own profile — used ONLY as a placeholder stand-in for
  /// demo leads that have no real incoming like ([liker] == null).
  final TenantProfile tenant;

  /// The real tenant who liked this property (representative/first liker). When
  /// present, the card renders THEIR name/photo/attributes — not the owner's.
  /// The deck is property-based, so it shows one liker per property; per-liker
  /// cards are a future enhancement.
  final PropertyLike? liker;

  final RentalProperty property;
  final List<AppReview> reviews;
  final int hOffset;
  final bool isHighFit;
  final String? fitReason;

  /// Honest fit score [0,100] for the compact ring/badge on the photo header.
  final double fitScore;

  /// How many OTHER tenants are interested in this property (beyond the one
  /// shown) — surfaced as a small "+N מתעניינים" pill so extra leads aren't lost.
  final int additionalInterested;

  // ── Effective display data: liker's real values when present, else the
  //    placeholder profile so demo leads keep rendering. ─────────────────────
  bool get _hasLiker => liker != null;

  String get _identity =>
      liker != null && liker!.tenantId.isNotEmpty ? liker!.tenantId : tenant.id;

  String get displayName =>
      (liker?.tenantName.isNotEmpty ?? false) ? liker!.tenantName : tenant.name;

  List<String> get displayPhotos {
    final photo = liker?.tenantPhotoUrl ?? '';
    if (liker != null) return photo.isEmpty ? const <String>[] : <String>[photo];
    return tenant.photoUrls;
  }

  int? get displayAge => _hasLiker ? liker!.age : tenant.age;

  int? get displayBudget {
    final b = liker?.budgetMax ?? (_hasLiker ? null : tenant.budgetMax);
    return (b != null && b > 0) ? b : null;
  }

  double? get displayRooms {
    final r = liker?.rooms ?? (_hasLiker ? null : tenant.desiredRooms);
    return (r != null && r > 0) ? r : null;
  }

  String? get displayMoveIn {
    final m = (liker?.moveInSnapshot.isNotEmpty ?? false)
        ? liker!.moveInSnapshot
        : (_hasLiker ? '' : tenant.moveInWindow);
    return m.isNotEmpty ? m : null;
  }

  String? displayOccupation(BuildContext context) {
    final o = _hasLiker ? liker!.occupation : tenant.occupation;
    return (o != null && o.isNotEmpty) ? _occupationLabel(context, o) : null;
  }

  String? displayHousehold(BuildContext context) {
    final h = _hasLiker ? liker!.household : tenant.household;
    return (h != null && h.isNotEmpty) ? _householdLabel(context, h) : null;
  }

  int? get displayNumChildren =>
      _hasLiker ? liker!.numChildren : tenant.numChildren;

  int? get displayIncome {
    final i = _hasLiker ? liker!.monthlyIncome : tenant.monthlyIncome;
    return (i != null && i > 0) ? i : null;
  }

  bool? get displayHasCar => _hasLiker ? liker!.hasCar : tenant.hasCar;
  bool? get displayHasPets => _hasLiker ? liker!.hasPets : tenant.hasPets;
  bool? get displayWfh => _hasLiker ? liker!.wfh : tenant.wfh;

  // Demo-lead placeholders carry no verification signal, so only a real liker
  // with an explicit verified flag shows the shield chip.
  bool get displayVerified => _hasLiker && (liker!.verified ?? false);

  /// The candidate's interest intent (from their urgency token), or null.
  String? get displayUrgency => _hasLiker ? liker!.urgency : tenant.urgency;

  @override
  State<_LeadCard> createState() => _LeadCardState();
}

class _LeadCardState extends State<_LeadCard> {
  int _photoIndex = 0;

  @override
  void didUpdateWidget(covariant _LeadCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._identity != widget._identity) {
      _photoIndex = 0;
      return;
    }
    _photoIndex = _safePhotoIndex(_photoIndex);
  }

  int _safePhotoIndex(int index) {
    final photoCount = widget.displayPhotos.length;
    if (photoCount <= 0) return 0;
    return index.clamp(0, photoCount - 1).toInt();
  }

  void _prevImage() {
    final current = _safePhotoIndex(_photoIndex);
    if (current > 0) setState(() => _photoIndex = current - 1);
  }

  void _nextImage() {
    final current = _safePhotoIndex(_photoIndex);
    if (current < widget.displayPhotos.length - 1) {
      setState(() => _photoIndex = current + 1);
    }
  }

  void _openDetail() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TenantDetailScreen(
          tenant: widget.tenant,
          property: widget.property,
          reviews: widget.reviews,
        ),
      ),
    );
  }

  // Candidate interest intent → a plain-language status the landlord can filter
  // by: actively looking vs checking options vs just browsing.
  String? _intentLabel(BuildContext context, String? token) {
    final l10n = AppLocalizations.of(context)!;
    switch (token) {
      case 'now':
        return l10n.exploreScreenCaab7e07;
      case 'soon':
        return l10n.exploreScreen861f28cc;
      case 'browsing':
        return l10n.exploreScreen9592be20;
      default:
        return null;
    }
  }

  /// The REAL, per-liker attribute facts — only non-null values are surfaced.
  List<_Fact> _buildFacts() {
    final l10n = AppLocalizations.of(context)!;
    final facts = <_Fact>[];
    // Interest intent first — it's the signal the landlord triages leads by.
    final intent = _intentLabel(context, widget.displayUrgency);
    if (intent != null) {
      facts.add(_Fact(IconsaxPlusLinear.flash, l10n.exploreScreen4189b321, intent));
    }
    final budget = widget.displayBudget;
    if (budget != null) {
      facts.add(_Fact(IconsaxPlusLinear.wallet_money, l10n.exploreScreen3bb32ddd, _fmt(budget)));
    }
    final rooms = widget.displayRooms;
    if (rooms != null) {
      final r = rooms.toStringAsFixed(rooms % 1 == 0 ? 0 : 1);
      facts.add(_Fact(IconsaxPlusLinear.building, l10n.exploreScreenB50b3974, l10n.exploreScreenF8eba562(r)));
    }
    final moveIn = widget.displayMoveIn;
    if (moveIn != null) {
      facts.add(_Fact(IconsaxPlusLinear.calendar, l10n.exploreScreen2f6783cd, moveIn));
    }
    final occupation = widget.displayOccupation(context);
    if (occupation != null) {
      facts.add(_Fact(IconsaxPlusLinear.briefcase, l10n.exploreScreen6b84e37c, occupation));
    }
    final household = widget.displayHousehold(context);
    final children = widget.displayNumChildren;
    if (household != null || (children != null && children > 0)) {
      final parts = <String>[
        if (household != null) household,
        if (children != null && children > 0) l10n.exploreScreenC60ce521(children),
      ];
      facts.add(_Fact(IconsaxPlusLinear.people, l10n.exploreScreen10f698cd, parts.join(' · ')));
    }
    final income = widget.displayIncome;
    if (income != null) {
      facts.add(_Fact(IconsaxPlusLinear.money_recive, l10n.exploreScreen07bf27d4, _fmt(income)));
    }
    final lifestyle = <String>[
      if (widget.displayHasCar == true) l10n.exploreScreen7f1643b2,
      if (widget.displayHasPets == true) l10n.exploreScreenAeee4760,
      if (widget.displayWfh == true) l10n.exploreScreenEcddc928,
    ];
    if (lifestyle.isNotEmpty) {
      facts.add(_Fact(IconsaxPlusLinear.car, l10n.exploreScreen7778a202, lifestyle.join(' · ')));
    }
    return facts;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isAccepting = widget.hOffset > 10;
    final isRejecting = widget.hOffset < -10;
    final facts = _buildFacts();
    final photos = widget.displayPhotos;
    final hasMultiple = photos.length > 1;
    final safePhotoIndex = _safePhotoIndex(_photoIndex);
    final currentPhoto = photos.isNotEmpty ? photos[safePhotoIndex] : '';
    final age = widget.displayAge;
    final nameLine =
        age != null ? '${widget.displayName}, $age' : widget.displayName;
    final fitReason = widget.fitReason;

    final dragFactor = (widget.hOffset.abs() / 100.0).clamp(0.0, 1.0);
    final blurRadius = 18.0 + (14.0 * dragFactor);
    final spreadRadius = 2.0 + (2.0 * dragFactor);
    final shadowOffset = Offset(0, 6.0 + (10.0 * dragFactor));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      child: GestureDetector(
        onTap: _openDetail,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withOpacity(0.16),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28 + (0.05 * dragFactor)),
                blurRadius: blurRadius,
                spreadRadius: spreadRadius,
                offset: shadowOffset,
              ),
              // Outward glass glow/reflection.
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
                // Full-bleed candidate photo carousel (mirrors ProfileCard).
                RepaintBoundary(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: SafeImage(
                      key: ValueKey(
                          '${widget._identity}:$safePhotoIndex:$currentPhoto'),
                      source: currentPhoto,
                      fallback: Container(
                        color: AppColors.navy,
                        child: const Center(
                          child: RentlyIcon(
                            IconsaxPlusLinear.profile_circle,
                            size: 72,
                            color: Colors.white24,
                          ),
                        ),
                      ),
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
                  ),
                ),

                // Top+bottom readability gradient (same as ProfileCard).
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.92),
                        Colors.black.withOpacity(0.65),
                        Colors.black.withOpacity(0.28),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.32, 0.60, 0.82],
                    ),
                  ),
                ),

                // Image-navigation tap zones (upper 55% of the card).
                if (hasMultiple)
                  Positioned.fill(
                    child: Column(
                      children: [
                        Expanded(
                          flex: 55,
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
                        const Expanded(flex: 45, child: SizedBox.shrink()),
                      ],
                    ),
                  ),

                // Stories-style progress bars at the very top.
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
                            margin:
                                const EdgeInsets.symmetric(horizontal: 2),
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

                // Top badges — fit-score ring (right) plus high-fit / verified
                // shield (left), styled like ProfileCard's badges.
                Positioned(
                  top: hasMultiple ? 24 : 14,
                  right: 14,
                  child: _FitBadge(score: widget.fitScore),
                ),
                if (widget.isHighFit ||
                    widget.displayVerified ||
                    widget.additionalInterested > 0)
                  Positioned(
                    top: hasMultiple ? 24 : 14,
                    left: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.isHighFit) _HighFitPill(),
                        if (widget.isHighFit && widget.displayVerified)
                          const SizedBox(height: 6),
                        if (widget.displayVerified) _VerifiedShield(),
                        if (widget.additionalInterested > 0) ...[
                          if (widget.isHighFit || widget.displayVerified)
                            const SizedBox(height: 6),
                          _MoreInterestedPill(count: widget.additionalInterested),
                        ],
                      ],
                    ),
                  ),

                // Swipe stamp (accept / reject).
                if (isAccepting || isRejecting)
                  Positioned(
                    top: 60,
                    left: isRejecting ? 24 : null,
                    right: isAccepting ? 24 : null,
                    child: Transform.rotate(
                      angle: isAccepting ? -0.18 : 0.18,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isAccepting
                                ? AppColors.primary
                                : AppColors.coral,
                            width: 3,
                          ),
                          color: (isAccepting
                                  ? AppColors.primary
                                  : AppColors.coral)
                              .withOpacity(0.08),
                        ),
                        child: Text(
                          isAccepting
                              ? l10n.exploreScreenFccc9519
                              : l10n.exploreScreen0d79bffc,
                          style: TextStyle(
                            color: isAccepting
                                ? AppColors.primary
                                : AppColors.coral,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Bottom info panel (same position/gradient as ProfileCard):
                // candidate name+age, a short fit reason, the interested-in
                // line and the rounded spec pills of real candidate facts.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 100,
                  child: GestureDetector(
                    onTap: _openDetail,
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Candidate name + age (the card title).
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            nameLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // "התעניין/ה ב: <property address>".
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              RentlyIcon(
                                IconsaxPlusLinear.heart,
                                size: 14,
                                color: Colors.white.withOpacity(0.6),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  l10n.exploreScreen046a972e(
                                      widget.property.address),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (fitReason != null) ...[
                          const SizedBox(height: 8),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                const Icon(IconsaxPlusBold.tick_circle,
                                    size: 14, color: AppColors.emerald),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    fitReason,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        // Rounded spec pills for the real candidate facts —
                        // same pill style as ProfileCard's stat pills.
                        if (facts.isNotEmpty)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                for (var i = 0; i < facts.length; i++) ...[
                                  if (i > 0) const SizedBox(width: 6),
                                  _SpecPill(
                                    icon: facts[i].icon,
                                    label: facts[i].value,
                                  ),
                                ],
                              ],
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
      ),
    );
  }
}

/// A single labeled attribute fact (icon + label + value).
class _Fact {
  const _Fact(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;
}

/// A rounded glass spec pill for a candidate fact — same style as
/// ProfileCard's stat pills (white translucent fill over the photo).
class _SpecPill extends StatelessWidget {
  const _SpecPill({required this.icon, required this.label});
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
          Icon(icon, size: 13, color: Colors.white.withOpacity(0.5)),
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

/// "התאמה גבוהה" top badge — the high-fit pill.
class _HighFitPill extends StatelessWidget {
  _HighFitPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(IconsaxPlusBold.medal_star, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(
            AppLocalizations.of(context)!.exploreScreen76b35661,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// "+N מתעניינים" pill — signals that more tenants are interested in this
/// property beyond the one on the card (Phase-0 per-liker awareness).
class _MoreInterestedPill extends StatelessWidget {
  const _MoreInterestedPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.navy.withOpacity(0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(IconsaxPlusBold.people, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(
            AppLocalizations.of(context)!.exploreScreen6c2b3afd(count),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Verified-profile shield top badge — teal pill, styled like ProfileCard's
/// verified-listing badge.
class _VerifiedShield extends StatelessWidget {
  _VerifiedShield();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(IconsaxPlusBold.shield_tick, color: Colors.white, size: 12),
          const SizedBox(width: 5),
          Text(
            AppLocalizations.of(context)!.exploreScreen7de9ac58,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact circular fit-score badge (e.g. "82%") shown on the photo header.
class _FitBadge extends StatelessWidget {
  const _FitBadge({required this.score});
  final double score;

  @override
  Widget build(BuildContext context) {
    final pct = score.clamp(0, 100).round();
    final color = _fitColor(score);
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$pct%',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// Fit-score → traffic-light color for the badge (honest, not fabricated).
Color _fitColor(double score) {
  if (score >= 75) return AppColors.success;
  if (score >= 50) return AppColors.carrot;
  return AppColors.coral;
}

// ─── Action buttons ───────────────────────────────────────────────────────────

/// A single circular swipe-action control with a scale-on-tap animation. Floats
/// over the deck bottom (reject / details / accept), mirroring discover.
// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyOwnerQueue extends StatelessWidget {
  _EmptyOwnerQueue({this.onGoToMessages});

  /// When set, "עבור לשיחות" switches the merged host to its הודעות segment
  /// instead of pushing a back-button-less MatchesScreen.
  final VoidCallback? onGoToMessages;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
            Text(
              l10n.exploreScreenA261278d,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasProperties
                  ? l10n.exploreScreen4d90eb93
                  : l10n.exploreScreen05ec83de,
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
                  label: Text(l10n.exploreScreen9bcc24df),
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
                  onPressed: () {
                    // Prefer switching the merged host's segment (keeps chrome +
                    // back affordance); fall back to the standalone push.
                    if (onGoToMessages != null) {
                      onGoToMessages!();
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            settings:
                                const RouteSettings(name: 'MatchesScreen'),
                            builder: (_) => const MatchesScreen()),
                      );
                    }
                  },
                  icon: const RentlyIcon(IconsaxPlusLinear.message, size: 17),
                  label: Text(l10n.exploreScreen567d5a67),
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

// ─── Candidate filters ────────────────────────────────────────────────────────

/// Thin, low-profile bar above the candidate deck. It holds the SINGLE entry to
/// the filter sheet (an icon button with an active-count badge) plus a compact
/// auto-like toggle. The old quick-chip row and the bulky auto-like card were
/// removed in favour of this minimal strip.
class _CandidateTopBar extends StatelessWidget {
  const _CandidateTopBar({
    required this.autoLikeEnabled,
    required this.onToggleAutoLike,
    required this.activeFilterCount,
    required this.showFilters,
    required this.onOpenFilters,
  });

  final bool autoLikeEnabled;
  final VoidCallback onToggleAutoLike;
  final int activeFilterCount;
  final bool showFilters;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Directionality(
        textDirection: Directionality.of(context),
        child: Row(
          children: [
            if (showFilters)
              _FiltersIconButton(
                count: activeFilterCount,
                onTap: onOpenFilters,
              ),
            const Spacer(),
            _AutoLikeToggle(
              enabled: autoLikeEnabled,
              onToggle: onToggleAutoLike,
            ),
          ],
        ),
      ),
    );
  }
}

/// The one and only entry point to the candidate filter sheet — a compact,
/// pill-shaped icon button that shows the active-filter count as a badge.
class _FiltersIconButton extends StatelessWidget {
  _FiltersIconButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.slate200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              IconsaxPlusLinear.setting_4,
              size: 16,
              color: active ? Colors.white : AppColors.navy,
            ),
            const SizedBox(width: 6),
            Text(
              AppLocalizations.of(context)!.exploreScreenEde0a5bb,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: active ? Colors.white : AppColors.navy,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Minimal auto-like indicator: a small label + a compact adaptive Switch.
/// Binds to [DatingProvider.autoLikeEnabled] / [DatingProvider.toggleAutoLike].
class _AutoLikeToggle extends StatelessWidget {
  _AutoLikeToggle({required this.enabled, required this.onToggle});

  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          IconsaxPlusBold.flash,
          size: 15,
          color: enabled ? AppColors.primary : AppColors.slate400,
        ),
        const SizedBox(width: 5),
        Text(
          AppLocalizations.of(context)!.exploreScreenB803dad3,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: enabled ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 4),
        Transform.scale(
          scale: 0.78,
          child: Switch.adaptive(
            value: enabled,
            activeColor: AppColors.primary,
            activeTrackColor: AppColors.primary.withOpacity(0.3),
            inactiveThumbColor: AppColors.slate400,
            inactiveTrackColor: AppColors.slate200,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (_) => onToggle(),
          ),
        ),
      ],
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.navy : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.navy : AppColors.slate200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 14, color: selected ? Colors.white : AppColors.navy),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Friendly empty state shown when active filters exclude every candidate.
class _NoMatchingCandidates extends StatelessWidget {
  _NoMatchingCandidates({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                IconsaxPlusLinear.filter_search,
                color: AppColors.primary,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.exploreScreenE335275c,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.exploreScreen86ad2dd3,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.6,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onClear,
                icon: const RentlyIcon(IconsaxPlusLinear.close_circle, size: 17),
                label: Text(l10n.exploreScreen9c08b083),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet with the fuller candidate-filter controls. Every control here
/// is now backed by real, per-liker data: the honest fit score, the liked
/// property's availability, plus the tenant's attribute snapshot carried on the
/// [PropertyLike] (occupation, household, #children, pets/car/WFH, income,
/// verification). Unknown (null) attributes never exclude a candidate.
class _CandidateFilterSheet extends StatefulWidget {
  _CandidateFilterSheet({required this.initial});

  final CandidateFilters initial;

  @override
  State<_CandidateFilterSheet> createState() => _CandidateFilterSheetState();
}

class _CandidateFilterSheetState extends State<_CandidateFilterSheet> {
  late CandidateFilters _draft = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.9;

    // ── Fit-score range (0–100). Full range = inactive on both ends. ─────────
    final fitStart = (_draft.minFitScore ?? 0).clamp(0, 100).toDouble();
    final fitEnd = (_draft.maxFitScore ?? 100).clamp(0, 100).toDouble();

    // ── Income (₪3,000 … ₪100,000+). Full-left = inactive. ──────────────────
    final incomeValue = (_draft.incomeMin ?? 3000).clamp(3000, 100000).toDouble();

    // ── Children (0 … 10+). At 10 = no limit (inactive). ────────────────────
    final childrenValue =
        (_draft.numChildrenMax ?? 10).clamp(0, 10).toDouble();

    // ── Budget range (₪2,000 … ₪20,000). Full range = inactive both ends. ───
    const budgetFloor = 2000.0;
    const budgetCeil = 20000.0;
    final budgetStart =
        (_draft.budgetMin ?? budgetFloor).clamp(budgetFloor, budgetCeil).toDouble();
    final budgetEnd =
        (_draft.budgetMax ?? budgetCeil).clamp(budgetFloor, budgetCeil).toDouble();

    // ── Age range (18 … 70). Full range = inactive both ends. ───────────────
    const ageFloor = 18.0;
    const ageCeil = 70.0;
    final ageStart =
        (_draft.ageMin ?? ageFloor).clamp(ageFloor, ageCeil).toDouble();
    final ageEnd = (_draft.ageMax ?? ageCeil).clamp(ageFloor, ageCeil).toDouble();

    // ── Minimum rooms chips (null = any). ───────────────────────────────────
    const roomsOptions = <double>[1, 1.5, 2, 2.5, 3, 4, 5];

    return Directionality(
      textDirection: Directionality.of(context),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.slate200,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ── Header: title (right) + close control (left) ──────────────
              Row(
                children: [
                  Text(
                    l10n.exploreScreenEde0a5bb,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
                    ),
                  ),
                  const Spacer(),
                  if (_draft.isNotEmpty)
                    GestureDetector(
                      onTap: () =>
                          setState(() => _draft = CandidateFilters.empty),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          l10n.exploreScreenEbbc108b,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  // Close (dismiss WITHOUT applying — the draft is discarded).
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        color: AppColors.slate100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 19,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Scrollable body so the fuller control set never overflows on
              // short devices; the handle, header and apply button stay pinned.
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Fit score (0–100 RANGE) ────────────────────────────
                      _sectionTitle(l10n.exploreScreen8f43e338, IconsaxPlusBold.medal_star),
                      const SizedBox(height: 4),
                      Text(
                        (_draft.minFitScore == null && _draft.maxFitScore == null)
                            ? l10n.exploreScreenDaf1cf49
                            : '${fitStart.round()}% – ${fitEnd.round()}%',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SliderTheme(
                        data: _sliderTheme(context),
                        child: RangeSlider(
                          values: RangeValues(fitStart, fitEnd),
                          min: 0,
                          max: 100,
                          divisions: 20,
                          labels: RangeLabels(
                            '${fitStart.round()}%',
                            '${fitEnd.round()}%',
                          ),
                          onChanged: (v) => setState(() {
                            if (v.start <= 0 && v.end >= 100) {
                              _draft = _draft.copyWith(
                                clearMinFitScore: true,
                                clearMaxFitScore: true,
                              );
                            } else {
                              _draft = _draft.copyWith(
                                minFitScore: v.start,
                                maxFitScore: v.end,
                              );
                            }
                          }),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Budget range (₪2,000 … ₪20,000) ────────────────────
                      _sectionTitle(l10n.exploreScreen4094ac8d,
                          IconsaxPlusLinear.money_recive),
                      const SizedBox(height: 4),
                      Text(
                        (_draft.budgetMin == null && _draft.budgetMax == null)
                            ? l10n.exploreScreenBe539fd6
                            : '${_fmt(budgetStart.round())} – ${_fmt(budgetEnd.round())}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SliderTheme(
                        data: _sliderTheme(context),
                        child: RangeSlider(
                          values: RangeValues(budgetStart, budgetEnd),
                          min: budgetFloor,
                          max: budgetCeil,
                          divisions: 36,
                          labels: RangeLabels(
                            _fmt(budgetStart.round()),
                            _fmt(budgetEnd.round()),
                          ),
                          onChanged: (v) => setState(() {
                            if (v.start <= budgetFloor && v.end >= budgetCeil) {
                              _draft = _draft.copyWith(
                                clearBudgetMin: true,
                                clearBudgetMax: true,
                              );
                            } else {
                              _draft = _draft.copyWith(
                                budgetMin: v.start,
                                budgetMax: v.end,
                              );
                            }
                          }),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Age range (18 … 70) ────────────────────────────────
                      _sectionTitle(l10n.exploreScreenE5aeca16, IconsaxPlusLinear.user),
                      const SizedBox(height: 4),
                      Text(
                        (_draft.ageMin == null && _draft.ageMax == null)
                            ? l10n.exploreScreenE5e69fd1
                            : '${ageStart.round()} – ${ageEnd.round()}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SliderTheme(
                        data: _sliderTheme(context),
                        child: RangeSlider(
                          values: RangeValues(ageStart, ageEnd),
                          min: ageFloor,
                          max: ageCeil,
                          divisions: 52,
                          labels: RangeLabels(
                            '${ageStart.round()}',
                            '${ageEnd.round()}',
                          ),
                          onChanged: (v) => setState(() {
                            if (v.start <= ageFloor && v.end >= ageCeil) {
                              _draft = _draft.copyWith(
                                clearAgeMin: true,
                                clearAgeMax: true,
                              );
                            } else {
                              _draft = _draft.copyWith(
                                ageMin: v.start.round(),
                                ageMax: v.end.round(),
                              );
                            }
                          }),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Minimum rooms (chips) ──────────────────────────────
                      _sectionTitle(l10n.exploreScreen5c2ad42a,
                          IconsaxPlusLinear.building),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final r in roomsOptions)
                            _QuickChip(
                              label:
                                  '${r.toStringAsFixed(r % 1 == 0 ? 0 : 1)}+',
                              selected: _draft.roomsMin == r,
                              onTap: () => setState(() {
                                _draft = _draft.roomsMin == r
                                    ? _draft.copyWith(clearRoomsMin: true)
                                    : _draft.copyWith(roomsMin: r);
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Life stage (multi-select) ──────────────────────────
                      _sectionTitle(l10n.exploreScreenD308ff19, IconsaxPlusLinear.user_octagon),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry
                              in CandidateFilters.lifeStageLabelsFor(l10n)
                                  .entries)
                            _QuickChip(
                              label: entry.value,
                              selected: _draft.lifeStage.contains(entry.key),
                              onTap: () => _toggleLifeStage(entry.key),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Recent likes only ──────────────────────────────────
                      _sectionTitle(l10n.exploreScreenFe95da03, IconsaxPlusLinear.clock),
                      const SizedBox(height: 12),
                      Wrap(
                        children: [
                          _QuickChip(
                            label: l10n.exploreScreen4b4fd824,
                            icon: IconsaxPlusLinear.flash_1,
                            selected: _draft.recentOnly,
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(
                                  recentOnly: !_draft.recentOnly);
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Monthly income (₪3,000 … ₪100,000+) ────────────────
                      _sectionTitle(l10n.exploreScreen959e2dfc,
                          IconsaxPlusLinear.wallet_money),
                      const SizedBox(height: 4),
                      Text(
                        _draft.incomeMin == null
                            ? l10n.exploreScreen07d495e1
                            : _incomeLabel(incomeValue),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SliderTheme(
                        data: _sliderTheme(context),
                        child: Slider(
                          value: incomeValue,
                          min: 3000,
                          max: 100000,
                          divisions: 97,
                          label: _incomeLabel(incomeValue),
                          onChanged: (v) => setState(() {
                            _draft = v <= 3000
                                ? _draft.copyWith(clearIncomeMin: true)
                                : _draft.copyWith(incomeMin: v);
                          }),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Number of children (0 … 10+) ───────────────────────
                      _sectionTitle(l10n.exploreScreenB0e336c6,
                          IconsaxPlusLinear.profile_2user),
                      const SizedBox(height: 4),
                      Text(
                        _draft.numChildrenMax == null
                            ? l10n.exploreScreen09ae3918
                            : l10n.exploreScreen8af90dc4(
                                _childrenLabel(childrenValue)),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SliderTheme(
                        data: _sliderTheme(context),
                        child: Slider(
                          value: childrenValue,
                          min: 0,
                          max: 10,
                          divisions: 10,
                          label: _childrenLabel(childrenValue),
                          onChanged: (v) => setState(() {
                            final n = v.round();
                            _draft = n >= 10
                                ? _draft.copyWith(clearNumChildrenMax: true)
                                : _draft.copyWith(numChildrenMax: n);
                          }),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Availability / move-in ─────────────────────────────
                      _sectionTitle(
                          l10n.exploreScreen61dc5b0a, IconsaxPlusLinear.calendar),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final token
                              in CandidateFilters.moveInWindowTokens)
                            _QuickChip(
                              label: CandidateFilters.moveInWindowLabel(
                                  l10n, token),
                              selected: _draft.moveInWindow == token,
                              onTap: () => setState(() {
                                _draft = _draft.moveInWindow == token
                                    ? _draft.copyWith(clearMoveInWindow: true)
                                    : _draft.copyWith(moveInWindow: token);
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Occupation (multi-select) ──────────────────────────
                      _sectionTitle(l10n.exploreScreen15039c05, IconsaxPlusLinear.briefcase),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in _occupationLabels(context).entries)
                            _QuickChip(
                              label: entry.value,
                              selected: _draft.occupation.contains(entry.key),
                              onTap: () => _toggleSet('occupation', entry.key),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Household type (multi-select) ──────────────────────
                      _sectionTitle(l10n.exploreScreen2b9fb355, IconsaxPlusLinear.people),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in _householdLabels(context).entries)
                            _QuickChip(
                              label: entry.value,
                              selected: _draft.household.contains(entry.key),
                              onTap: () => _toggleSet('household', entry.key),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Lifestyle toggles (pets / car / WFH) ───────────────
                      _sectionTitle(l10n.exploreScreen7778a202, IconsaxPlusLinear.pet),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _QuickChip(
                            label: l10n.exploreScreenE70cb0b4,
                            icon: IconsaxPlusLinear.pet,
                            selected: _draft.hasPets == false,
                            onTap: () => setState(() {
                              _draft = _draft.hasPets == false
                                  ? _draft.copyWith(clearHasPets: true)
                                  : _draft.copyWith(hasPets: false);
                            }),
                          ),
                          _QuickChip(
                            label: l10n.exploreScreen7decda58,
                            icon: IconsaxPlusLinear.car,
                            selected: _draft.hasCar == true,
                            onTap: () => setState(() {
                              _draft = _draft.hasCar == true
                                  ? _draft.copyWith(clearHasCar: true)
                                  : _draft.copyWith(hasCar: true);
                            }),
                          ),
                          _QuickChip(
                            label: l10n.exploreScreenEcddc928,
                            icon: IconsaxPlusLinear.home_2,
                            selected: _draft.wfh == true,
                            onTap: () => setState(() {
                              _draft = _draft.wfh == true
                                  ? _draft.copyWith(clearWfh: true)
                                  : _draft.copyWith(wfh: true);
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Religious lifestyle fit (חילוני…חרדי) ──────────────
                      _sectionTitle(l10n.exploreScreen7778a202, IconsaxPlusLinear.candle),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final e in _kLifestyleLabels.entries)
                            _QuickChip(
                              label: e.value,
                              selected:
                                  _draft.religiousLifestyle.contains(e.key),
                              onTap: () =>
                                  _toggleSet('religiousLifestyle', e.key),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Religious deal-breakers (Shabbat / kosher) ─────────
                      _sectionTitle(l10n.exploreScreen81d92174, IconsaxPlusLinear.moon),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _QuickChip(
                            label: l10n.exploreScreen8ac14f86,
                            icon: IconsaxPlusLinear.moon,
                            selected: _draft.shabbatObservant == true,
                            onTap: () => setState(() {
                              _draft = _draft.shabbatObservant == true
                                  ? _draft.copyWith(clearShabbatObservant: true)
                                  : _draft.copyWith(shabbatObservant: true);
                            }),
                          ),
                          _QuickChip(
                            label: l10n.exploreScreen30524972,
                            icon: IconsaxPlusLinear.reserve,
                            selected: _draft.keepsKosher == true,
                            onTap: () => setState(() {
                              _draft = _draft.keepsKosher == true
                                  ? _draft.copyWith(clearKeepsKosher: true)
                                  : _draft.copyWith(keepsKosher: true);
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Pet policy (allow-list — permit a cat, exclude a big dog)
                      _sectionTitle(l10n.exploreScreen00549c82, IconsaxPlusLinear.pet),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final e in _kPetTypeLabels.entries)
                            _QuickChip(
                              label: e.value,
                              selected: _draft.petTypes.contains(e.key),
                              onTap: () => _toggleSet('petTypes', e.key),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Noise deal-breakers (hosting / instrument) ─────────
                      _sectionTitle(l10n.exploreScreenD2ab88e9, IconsaxPlusLinear.volume_low),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _QuickChip(
                            label: l10n.exploreScreenB9558dae,
                            icon: IconsaxPlusLinear.profile_2user,
                            selected: _draft.hostsGuests == false,
                            onTap: () => setState(() {
                              _draft = _draft.hostsGuests == false
                                  ? _draft.copyWith(clearHostsGuests: true)
                                  : _draft.copyWith(hostsGuests: false);
                            }),
                          ),
                          _QuickChip(
                            label: l10n.exploreScreen73940096,
                            icon: IconsaxPlusLinear.music,
                            selected: _draft.playsInstrument == false,
                            onTap: () => setState(() {
                              _draft = _draft.playsInstrument == false
                                  ? _draft.copyWith(clearPlaysInstrument: true)
                                  : _draft.copyWith(playsInstrument: false);
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Affordability: income-to-rent ratio ────────────────
                      _sectionTitle(l10n.exploreScreen01759509,
                          IconsaxPlusLinear.chart_success),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final r in const <double>[2.0, 2.5, 3.0])
                            _QuickChip(
                              label: l10n.exploreScreen7e55dfd4(
                                  r.toStringAsFixed(r % 1 == 0 ? 0 : 1)),
                              selected: _draft.minIncomeToRentRatio == r,
                              onTap: () => setState(() {
                                _draft = _draft.minIncomeToRentRatio == r
                                    ? _draft.copyWith(
                                        clearMinIncomeToRentRatio: true)
                                    : _draft.copyWith(minIncomeToRentRatio: r);
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── New immigrant (עולה חדש) ──────────────────────────
                      _sectionTitle(l10n.exploreScreen5f3306da, IconsaxPlusLinear.global),
                      const SizedBox(height: 12),
                      Wrap(
                        children: [
                          _QuickChip(
                            label: l10n.exploreScreenCe24a1b8,
                            icon: IconsaxPlusLinear.global,
                            selected: _draft.oleh == true,
                            onTap: () => setState(() {
                              _draft = _draft.oleh == true
                                  ? _draft.copyWith(clearOleh: true)
                                  : _draft.copyWith(oleh: true);
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Commute distance from work ─────────────────────────
                      _sectionTitle(l10n.exploreScreenC48f4680,
                          IconsaxPlusLinear.location),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final km in const <double>[5, 10, 20])
                            _QuickChip(
                              label: l10n.exploreScreen9b92340a(km.round()),
                              selected: _draft.maxCommuteKm == km,
                              onTap: () => setState(() {
                                _draft = _draft.maxCommuteKm == km
                                    ? _draft.copyWith(clearMaxCommuteKm: true)
                                    : _draft.copyWith(maxCommuteKm: km);
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Smoking ────────────────────────────────────────────
                      _sectionTitle(l10n.exploreScreen2a6f2e2a, IconsaxPlusLinear.forbidden_2),
                      const SizedBox(height: 12),
                      Wrap(
                        children: [
                          _QuickChip(
                            label: l10n.exploreScreen5ad0c26b,
                            icon: IconsaxPlusLinear.forbidden_2,
                            selected: _draft.smoker == false,
                            onTap: () => setState(() {
                              _draft = _draft.smoker == false
                                  ? _draft.copyWith(clearSmoker: true)
                                  : _draft.copyWith(smoker: false);
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Guarantor (ערב) ────────────────────────────────────
                      _sectionTitle(l10n.exploreScreenA5928b66, IconsaxPlusLinear.user_tick),
                      const SizedBox(height: 12),
                      Wrap(
                        children: [
                          _QuickChip(
                            label: l10n.exploreScreenD7297c85,
                            icon: IconsaxPlusLinear.user_tick,
                            selected: _draft.hasGuarantor == true,
                            onTap: () => setState(() {
                              _draft = _draft.hasGuarantor == true
                                  ? _draft.copyWith(clearHasGuarantor: true)
                                  : _draft.copyWith(hasGuarantor: true);
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Desired lease length ───────────────────────────────
                      _sectionTitle(l10n.exploreScreen9d40aa19,
                          IconsaxPlusLinear.calendar_1),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final m in const <int>[6, 12, 24])
                            _QuickChip(
                              label: l10n.exploreScreenAb462e4c(m),
                              selected: _draft.minLeaseMonths == m,
                              onTap: () => setState(() {
                                _draft = _draft.minLeaseMonths == m
                                    ? _draft.copyWith(clearMinLeaseMonths: true)
                                    : _draft.copyWith(minLeaseMonths: m);
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Income proof ready ─────────────────────────────────
                      _sectionTitle(l10n.exploreScreenAfe8dc6a,
                          IconsaxPlusLinear.document_text),
                      const SizedBox(height: 12),
                      Wrap(
                        children: [
                          _QuickChip(
                            label: l10n.exploreScreenA60a4948,
                            icon: IconsaxPlusLinear.document_text,
                            selected: _draft.incomeProofReady == true,
                            onTap: () => setState(() {
                              _draft = _draft.incomeProofReady == true
                                  ? _draft.copyWith(clearIncomeProofReady: true)
                                  : _draft.copyWith(incomeProofReady: true);
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Verified only ──────────────────────────────────────
                      _sectionTitle(
                          l10n.exploreScreen45e673e6, IconsaxPlusLinear.shield_tick),
                      const SizedBox(height: 12),
                      Wrap(
                        children: [
                          _QuickChip(
                            label: l10n.exploreScreenD6dcc370,
                            icon: IconsaxPlusLinear.shield_tick,
                            selected: _draft.verifiedOnly,
                            onTap: () => setState(() {
                              _draft = _draft.copyWith(
                                  verifiedOnly: !_draft.verifiedOnly);
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ── Bottom actions: clear-all + apply ─────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _draft.isNotEmpty
                          ? () => setState(() => _draft = CandidateFilters.empty)
                          : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.navy,
                        side: const BorderSide(color: AppColors.borderLight),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(l10n.exploreScreenEbbc108b),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_draft),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        l10n.exploreScreen5c514c37,
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  SliderThemeData _sliderTheme(BuildContext context) =>
      SliderTheme.of(context).copyWith(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.slate200,
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primary.withOpacity(0.12),
        valueIndicatorColor: AppColors.primary,
      );

  /// "₪3,000" … "₪100,000+" (the "+" appears at the ceiling).
  String _incomeLabel(double v) =>
      v >= 100000 ? '${_fmt(100000)}+' : _fmt(v.round());

  /// "0" … "10+" (the "+" appears at the ceiling = no limit).
  String _childrenLabel(double v) => v >= 10 ? '10+' : '${v.round()}';

  /// Toggles membership of [key] in the [field] set ('occupation' | 'household')
  /// and stores the updated set on the draft.
  void _toggleSet(String field, String key) {
    final current = switch (field) {
      'occupation' => _draft.occupation,
      'religiousLifestyle' => _draft.religiousLifestyle,
      'petTypes' => _draft.petTypes,
      _ => _draft.household,
    };
    final next = Set<String>.from(current);
    if (next.contains(key)) {
      next.remove(key);
    } else {
      next.add(key);
    }
    setState(() {
      _draft = switch (field) {
        'occupation' => _draft.copyWith(occupation: next),
        'religiousLifestyle' => _draft.copyWith(religiousLifestyle: next),
        'petTypes' => _draft.copyWith(petTypes: next),
        _ => _draft.copyWith(household: next),
      };
    });
  }

  /// Toggles a life-stage key in the draft's [CandidateFilters.lifeStage] set.
  void _toggleLifeStage(String key) {
    final next = Set<String>.from(_draft.lifeStage);
    if (next.contains(key)) {
      next.remove(key);
    } else {
      next.add(key);
    }
    setState(() => _draft = _draft.copyWith(lifeStage: next));
  }

  Widget _sectionTitle(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
        ),
      ],
    );
  }
}

// ─── Candidate attribute vocabularies (mirror the tenant profile editor) ──────

/// Occupation keys → localized label, matching the tenant profile / eligibility
/// vocabulary so a liker's stored key renders and filters correctly.
Map<String, String> _occupationLabels(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return <String, String>{
    'hightech': l10n.exploreScreen40d56dee,
    'healthcare': l10n.exploreScreen6dfb51f1,
    'education': l10n.exploreScreen19981c32,
    'finance': l10n.exploreScreenEbfcd4cb,
    'law': l10n.exploreScreen4f8aded7,
    'engineering': l10n.exploreScreen453fe1ed,
    'selfemployed': l10n.exploreScreenE1cad55a,
    'public': l10n.exploreScreenCb481f30,
    'retail': l10n.exploreScreen2834587d,
    'academia': l10n.exploreScreen2157ec10,
    'student': l10n.exploreScreen42ed7e8d,
    'other': l10n.exploreScreenCdf4bce0,
  };
}

Map<String, String> _householdLabels(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return <String, String>{
    'family': l10n.exploreScreen926c043f,
    'single': l10n.exploreScreenB8d9266b,
    'couple': l10n.exploreScreen4df994d0,
    'student': l10n.exploreScreen42ed7e8d,
  };
}

// kLifestyleLabels / kPetTypeLabels live in rental_models.dart (shared with the
// tenant profile capture). Local aliases keep the sheet code terse.
const Map<String, String> _kLifestyleLabels = kLifestyleLabels;
const Map<String, String> _kPetTypeLabels = kPetTypeLabels;

String _occupationLabel(BuildContext context, String key) =>
    _occupationLabels(context)[key] ?? key;

String _householdLabel(BuildContext context, String key) =>
    _householdLabels(context)[key] ?? key;

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
