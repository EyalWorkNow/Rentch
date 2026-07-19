import 'dart:math' as math;
import 'package:dating_app/core/ui/platform_fx.dart';
import 'dart:ui';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/candidate_filters.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/data/repositories/property_likes_repository.dart';
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

  /// The representative liker for a property lead — the first tenant who liked
  /// it. The candidate deck is property-based, so it surfaces one liker per
  /// property; per-liker cards are a future enhancement. Returns null for demo
  /// leads that have no real incoming like yet.
  PropertyLike? _representativeLiker(
      DatingProvider provider, RentalProperty property) {
    final likes = provider.incomingLikesFor(property.id);
    return likes.isEmpty ? null : likes.first;
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
      income: liker?.monthlyIncome?.toDouble(),
      verified: liker?.verified,
    );
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
        final tenant = provider.tenantProfile;
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
                    'מועמדים',
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
                      _buildAutoLikeCard(provider),
                      if (allLeads.isNotEmpty)
                        _CandidateFilterBar(
                          filters: _filters,
                          onQuickChange: _setFilters,
                          onOpenSheet: () => _openFilterSheet(provider),
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
                                  // Full-height card swiper
                                  Positioned.fill(
                                    child: CardSwiper(
                                      key: ValueKey(leads.map((p) => p.id).join('-')),
                                      controller: provider.ownerSwiperController,
                                      cardsCount: leads.length,
                                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 150),
                                      scale: 0.93,
                                      threshold: 38,
                                      maxAngle: 16,
                                      isLoop: false,
                                      numberOfCardsDisplayed: math.min(3, leads.length),
                                      backCardOffset: const Offset(0, 20),
                                      allowedSwipeDirection: const AllowedSwipeDirection.only(
                                        left: true,
                                        right: true,
                                        up: true,
                                      ),
                                      onSwipe: (prev, current, dir) {
                                        // The deck's ValueKey is derived from the
                                        // visible ids, so accept/reject shrinks the
                                        // list and the CardSwiper fully resets to
                                        // its internal index 0 (top card). Mirror
                                        // that here — using [current] would leave
                                        // _currentIndex stale and point the counter
                                        // + ⓘ button at the wrong candidate.
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
                                      cardBuilder: (context, index, hOffset, vOffset) {
                                        if (index < 0 || index >= leads.length) {
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
                                        );
                                      },
                                    ),
                                  ),

                                  // Floating centered action buttons
                                  Positioned(
                                    bottom: 165,
                                    left: 0,
                                    right: 0,
                                    child: _ActionButtons(
                                      onReject: () {
                                        HapticFeedback.mediumImpact();
                                        provider.ownerSwipeLeft();
                                      },
                                      onAccept: () {
                                        HapticFeedback.heavyImpact();
                                        provider.ownerSwipeRight();
                                      },
                                      onInfo: () {
                                        if (leads.isEmpty || safeIndex >= leads.length) return;
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => TenantDetailScreen(
                                              tenant: tenant,
                                              property: leads[safeIndex],
                                              reviews: provider.tenantReviews,
                                            ),
                                          ),
                                        );
                                      },
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

  Widget _buildAutoLikeCard(DatingProvider provider) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 12, 18, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: provider.autoLikeEnabled
              ? [
                  AppColors.primary.withOpacity(0.08),
                  AppColors.tealBrand.withOpacity(0.04),
                ]
              : [
                  Colors.white.withOpacity(0.9),
                  Colors.white.withOpacity(0.95),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: provider.autoLikeEnabled
              ? AppColors.primary.withOpacity(0.3)
              : AppColors.slate200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: provider.autoLikeEnabled
                ? AppColors.primary.withOpacity(0.08)
                : Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: provider.autoLikeEnabled
                  ? AppColors.primary.withOpacity(0.12)
                  : AppColors.slate100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              IconsaxPlusBold.flash,
              color: provider.autoLikeEnabled ? AppColors.primary : AppColors.textSecondary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'לייק אוטומטי',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'אישור אוטומטי של שוכרים שהתעניינו בנכס שלך',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: provider.autoLikeEnabled,
            activeColor: AppColors.primary,
            activeTrackColor: AppColors.primary.withOpacity(0.3),
            inactiveThumbColor: AppColors.slate400,
            inactiveTrackColor: AppColors.slate200,
            onChanged: (val) {
              HapticFeedback.mediumImpact();
              provider.toggleAutoLike();
            },
          ),
        ],
      ),
    );
  }

  Color _trustColor(int score) {
    if (score >= 80) return AppColors.success;
    if (score >= 50) return const Color(0xFFE67E22);
    return AppColors.coral;
  }
}

// ─── Lead Card ────────────────────────────────────────────────────────────────

class _LeadCard extends StatefulWidget {
  const _LeadCard({
    required this.tenant,
    required this.liker,
    required this.property,
    required this.reviews,
    required this.hOffset,
    required this.isHighFit,
    required this.fitReason,
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

  // ── Effective display data: liker's real values when present, else the
  //    placeholder profile so demo leads keep rendering. ─────────────────────
  String get _identity =>
      liker != null && liker!.tenantId.isNotEmpty ? liker!.tenantId : tenant.id;

  String get displayName =>
      (liker?.tenantName.isNotEmpty ?? false) ? liker!.tenantName : tenant.name;

  List<String> get displayPhotos {
    final photo = liker?.tenantPhotoUrl ?? '';
    if (liker != null) return photo.isEmpty ? const <String>[] : <String>[photo];
    return tenant.photoUrls;
  }

  int get displayBudget => liker?.budgetMax ?? tenant.budgetMax;

  double get displayRooms => liker?.rooms ?? tenant.desiredRooms;

  String get displayMoveIn => (liker?.moveInSnapshot.isNotEmpty ?? false)
      ? liker!.moveInSnapshot
      : tenant.moveInWindow;

  /// A short attribute pill: the liker's occupation (Hebrew label) when known,
  /// otherwise the placeholder profile's first "important detail".
  String? get displayDetail {
    final occ = liker?.occupation;
    if (occ != null && occ.isNotEmpty) return _occupationLabel(occ);
    if (tenant.importantDetails.isNotEmpty) return tenant.importantDetails.first;
    return null;
  }

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

  @override
  Widget build(BuildContext context) {
    final isAccepting = widget.hOffset > 10;
    final isRejecting = widget.hOffset < -10;
    final photos = widget.displayPhotos;
    final hasMultiple = photos.length > 1;
    final safePhotoIndex = _safePhotoIndex(_photoIndex);
    final currentPhoto = photos.isNotEmpty ? photos[safePhotoIndex] : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withOpacity(0.16),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.28),
              blurRadius: 18,
              spreadRadius: 2,
              offset: const Offset(0, 6),
            ),
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
              // Main Image
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: SafeImage(
                  key: ValueKey('${widget._identity}:$safePhotoIndex:$currentPhoto'),
                  source: currentPhoto,
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
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
              ),

              // Bottom dark gradient overlay
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black87,
                      Colors.black54,
                      Colors.black26,
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.35, 0.65, 0.85],
                  ),
                ),
              ),

              // Image navigation tap zones
              if (hasMultiple)
                Positioned.fill(
                  child: Column(
                    children: [
                      Expanded(
                        flex: 60,
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
                      const Spacer(flex: 40),
                    ],
                  ),
                ),

              // Tap bottom area -> detail page
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: MediaQuery.sizeOf(context).height * 0.32,
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TenantDetailScreen(
                          tenant: widget.tenant,
                          property: widget.property,
                          reviews: widget.reviews,
                        ),
                      ),
                    );
                  },
                  behavior: HitTestBehavior.translucent,
                ),
              ),

              // Stories-style progress bars
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
                          margin: const EdgeInsets.symmetric(horizontal: 2),
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

              // Top row: trust score or verification status badge
              Positioned(
                top: hasMultiple ? 26 : 16,
                right: 16,
                left: 16,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            IconsaxPlusLinear.shield_tick,
                            color: AppColors.primary,
                            size: 13,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'פרופיל מאומת',
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.isHighFit) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              IconsaxPlusBold.medal_star,
                              color: Colors.white,
                              size: 13,
                            ),
                            SizedBox(width: 5),
                            Text(
                              'התאמה גבוהה',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TenantDetailScreen(
                              tenant: widget.tenant,
                              property: widget.property,
                              reviews: widget.reviews,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.42),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
                          ),
                        ),
                        child: const Icon(
                          Icons.info_outline_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Swipe overlays
              if (isAccepting || isRejecting)
                Positioned(
                  top: 28,
                  left: isRejecting ? 22 : null,
                  right: isAccepting ? 22 : null,
                  child: Transform.rotate(
                    angle: isAccepting ? -0.15 : 0.15,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isAccepting ? AppColors.primary : AppColors.coral,
                          width: 3,
                        ),
                        color: (isAccepting ? AppColors.primary : AppColors.coral).withOpacity(0.08),
                      ),
                      child: Text(
                        isAccepting ? '✓ מאשר' : '✕ דוחה',
                        style: TextStyle(
                          color: isAccepting ? AppColors.primary : AppColors.coral,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),

              // Bottom Info Content
              Positioned(
                left: 16,
                right: 16,
                bottom: 128,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.displayName,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    if (widget.fitReason != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            IconsaxPlusBold.tick_circle,
                            color: AppColors.tealLight,
                            size: 14,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              widget.fitReason!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.tealLight,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _fmt(widget.displayBudget),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '/ לחודש',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _LikedPropertyBox(property: widget.property),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _StatPill(
                            icon: IconsaxPlusLinear.building,
                            label: '${widget.displayRooms.toStringAsFixed(widget.displayRooms % 1 == 0 ? 0 : 1)} חדרים',
                          ),
                          const SizedBox(width: 6),
                          _StatPill(
                            icon: IconsaxPlusLinear.calendar,
                            label: widget.displayMoveIn,
                          ),
                          if (widget.displayDetail != null) ...[
                            const SizedBox(width: 6),
                            _StatPill(
                              icon: IconsaxPlusLinear.info_circle,
                              label: widget.displayDetail!,
                            ),
                          ],
                        ],
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
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.label});
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
          Icon(icon, size: 13, color: Colors.white.withOpacity(0.6)),
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

// ─── Liked property box ───────────────────────────────────────────────────────

class _LikedPropertyBox extends StatelessWidget {
  const _LikedPropertyBox({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(10), sigmaY: PlatformFx.blurSigma(10)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.tealBrand.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: RentlyIcon(
                    IconsaxPlusLinear.heart,
                    size: 16,
                    color: AppColors.tealLight,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'התעניין/ה בנכס:',
                      style: TextStyle(
                        color: AppColors.tealLight,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      property.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  property.priceLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
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

// ─── Action Buttons ───────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.onReject,
    required this.onAccept,
    required this.onInfo,
  });

  final VoidCallback onReject;
  final VoidCallback onAccept;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 56),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Accept button (Right in RTL)
          _ActionButton(
            icon: IconsaxPlusBold.heart,
            tooltip: 'אשר מועמד',
            // White heart on a solid accent circle — readable for every theme
            // (broker's accent is black, so a black-on-white heart was invisible).
            iconColor: Colors.white,
            backgroundColor: AppColors.primary,
            size: 72,
            iconSize: 34,
            onPressed: onAccept,
            shadowColor: AppColors.primary,
          ),

          // Detail / Info (Center)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionButton(
                icon: Icons.info_outline_rounded,
                tooltip: 'הצג פרטים מלאים',
                iconColor: AppColors.navy,
                backgroundColor: Colors.white,
                size: 56,
                iconSize: 26,
                onPressed: onInfo,
                shadowColor: AppColors.navy,
              ),
              const SizedBox(height: 6),
              Text(
                'פרטים',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),

          // Reject button (Left in RTL)
          _ActionButton(
            icon: Icons.close_rounded,
            tooltip: 'דחה מועמד',
            iconColor: AppColors.coral,
            backgroundColor: Colors.white,
            size: 62,
            iconSize: 30,
            onPressed: onReject,
            shadowColor: AppColors.coral,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.iconColor,
    required this.backgroundColor,
    required this.size,
    required this.iconSize,
    required this.onPressed,
    this.shadowColor,
  });

  final IconData icon;
  final String tooltip;
  final Color iconColor;
  final Color backgroundColor;
  final double size;
  final double iconSize;
  final VoidCallback onPressed;
  final Color? shadowColor;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkCenter = widget.iconColor == AppColors.navy;
    final actualIconColor = isDarkCenter ? Colors.white : widget.iconColor;

    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) async {
          await _ctrl.reverse();
          widget.onPressed();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (widget.shadowColor ?? Colors.black).withOpacity(0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(16), sigmaY: PlatformFx.blurSigma(16)),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.22),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      widget.icon,
                      size: widget.iconSize,
                      color: actualIconColor,
                    ),
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

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyOwnerQueue extends StatelessWidget {
  const _EmptyOwnerQueue({this.onGoToMessages});

  /// When set, "עבור לשיחות" switches the merged host to its הודעות segment
  /// instead of pushing a back-button-less MatchesScreen.
  final VoidCallback? onGoToMessages;

  @override
  Widget build(BuildContext context) {
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
            const Text(
              'אין מועמדים חדשים',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasProperties
                  ? 'כאשר שוכרים יאהבו את הנכסים שלך הם יופיעו כאן לאישור.'
                  : 'הוסף נכס ראשון — שוכרים שיאהבו אותו יופיעו כאן.',
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
                  label: const Text('הוסף נכס עכשיו'),
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
                  label: const Text('עבור לשיחות'),
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

/// Compact quick-chip row + "מסננים" button above the deck. The chips cover the
/// most common candidate filters (high fit, immediate availability, verified,
/// no pets) — all backed by real per-liker data; the fuller sheet is opened via
/// [onOpenSheet].
class _CandidateFilterBar extends StatelessWidget {
  const _CandidateFilterBar({
    required this.filters,
    required this.onQuickChange,
    required this.onOpenSheet,
  });

  final CandidateFilters filters;
  final ValueChanged<CandidateFilters> onQuickChange;
  final VoidCallback onOpenSheet;

  static const double _highFit = 70;

  @override
  Widget build(BuildContext context) {
    final isAll = filters.isEmpty;
    final highFitOn = filters.minFitScore != null;
    final immediateOn = filters.moveInWindow == 'immediate';
    final verifiedOn = filters.verifiedOnly;
    final noPetsOn = filters.hasPets == false;
    final count = filters.activeCount;

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 4, 18, 6),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: false,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _QuickChip(
                      label: 'הכל',
                      selected: isAll,
                      onTap: () => onQuickChange(CandidateFilters.empty),
                    ),
                    const SizedBox(width: 8),
                    _QuickChip(
                      label: 'התאמה גבוהה',
                      icon: IconsaxPlusBold.medal_star,
                      selected: highFitOn,
                      onTap: () => onQuickChange(
                        highFitOn
                            ? filters.copyWith(clearMinFitScore: true)
                            : filters.copyWith(minFitScore: _highFit),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _QuickChip(
                      label: 'פנוי מיידית',
                      icon: IconsaxPlusLinear.calendar_tick,
                      selected: immediateOn,
                      onTap: () => onQuickChange(
                        immediateOn
                            ? filters.copyWith(clearMoveInWindow: true)
                            : filters.copyWith(moveInWindow: 'immediate'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _QuickChip(
                      label: 'מאומת',
                      icon: IconsaxPlusLinear.shield_tick,
                      selected: verifiedOn,
                      onTap: () => onQuickChange(
                        filters.copyWith(verifiedOnly: !verifiedOn),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _QuickChip(
                      label: 'ללא חיות מחמד',
                      icon: IconsaxPlusLinear.pet,
                      selected: noPetsOn,
                      onTap: () => onQuickChange(
                        noPetsOn
                            ? filters.copyWith(clearHasPets: true)
                            : filters.copyWith(hasPets: false),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onOpenSheet,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: count > 0 ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: count > 0 ? AppColors.primary : AppColors.slate200,
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
                      color: count > 0 ? Colors.white : AppColors.navy,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'מסננים',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: count > 0 ? Colors.white : AppColors.navy,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
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
            ),
          ],
        ),
      ),
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
  const _NoMatchingCandidates({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
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
            const Text(
              'אין מועמדים שתואמים למסננים',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'נסה להרחיב את המסננים כדי לראות עוד מתעניינים.',
              textAlign: TextAlign.center,
              style: TextStyle(
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
                label: const Text('נקה מסננים'),
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
  const _CandidateFilterSheet({required this.initial});

  final CandidateFilters initial;

  @override
  State<_CandidateFilterSheet> createState() => _CandidateFilterSheetState();
}

class _CandidateFilterSheetState extends State<_CandidateFilterSheet> {
  late CandidateFilters _draft = widget.initial;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  'מסננים',
                  style: TextStyle(
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
                    child: Text(
                      'נקה הכל',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Scrollable so the fuller control set never overflows on short
            // devices; the grab handle, title and apply button stay pinned.
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Fit score ───────────────────────────────────────────
                    _sectionTitle('רמת התאמה', IconsaxPlusBold.medal_star),
                    const SizedBox(height: 6),
                    Text(
                      _draft.minFitScore == null
                          ? 'כל רמות ההתאמה'
                          : 'התאמה של ${_draft.minFitScore!.round()}% ומעלה',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: AppColors.slate200,
                        thumbColor: AppColors.primary,
                        overlayColor: AppColors.primary.withOpacity(0.12),
                      ),
                      child: Slider(
                        value: (_draft.minFitScore ?? 0).clamp(0, 100),
                        min: 0,
                        max: 100,
                        divisions: 20,
                        label: '${(_draft.minFitScore ?? 0).round()}%',
                        onChanged: (v) => setState(() {
                          _draft = v <= 0
                              ? _draft.copyWith(clearMinFitScore: true)
                              : _draft.copyWith(minFitScore: v);
                        }),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Availability / move-in ──────────────────────────────
                    _sectionTitle('מועד כניסה לנכס', IconsaxPlusLinear.calendar),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final token in CandidateFilters.moveInWindowTokens)
                          _QuickChip(
                            label: CandidateFilters.moveInWindowLabel(token),
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

                    // ── Occupation (multi-select) ───────────────────────────
                    _sectionTitle('תחום עיסוק', IconsaxPlusLinear.briefcase),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in _kOccupationLabels.entries)
                          _QuickChip(
                            label: entry.value,
                            selected: _draft.occupation.contains(entry.key),
                            onTap: () => _toggleSet('occupation', entry.key),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Household type (multi-select) ───────────────────────
                    _sectionTitle('סוג משק בית', IconsaxPlusLinear.people),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in _kHouseholdLabels.entries)
                          _QuickChip(
                            label: entry.value,
                            selected: _draft.household.contains(entry.key),
                            onTap: () => _toggleSet('household', entry.key),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Max #children ───────────────────────────────────────
                    _sectionTitle('מספר ילדים (מקסימום)',
                        IconsaxPlusLinear.profile_2user),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final n in const [0, 1, 2, 3, 4])
                          _QuickChip(
                            label: n == 0 ? 'ללא ילדים' : 'עד $n',
                            selected: _draft.numChildrenMax == n,
                            onTap: () => setState(() {
                              _draft = _draft.numChildrenMax == n
                                  ? _draft.copyWith(clearNumChildrenMax: true)
                                  : _draft.copyWith(numChildrenMax: n);
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Lifestyle toggles (pets / car / WFH) ────────────────
                    _sectionTitle('אורח חיים', IconsaxPlusLinear.pet),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _QuickChip(
                          label: 'ללא חיית מחמד',
                          icon: IconsaxPlusLinear.pet,
                          selected: _draft.hasPets == false,
                          onTap: () => setState(() {
                            _draft = _draft.hasPets == false
                                ? _draft.copyWith(clearHasPets: true)
                                : _draft.copyWith(hasPets: false);
                          }),
                        ),
                        _QuickChip(
                          label: 'בעל/ת רכב',
                          icon: IconsaxPlusLinear.car,
                          selected: _draft.hasCar == true,
                          onTap: () => setState(() {
                            _draft = _draft.hasCar == true
                                ? _draft.copyWith(clearHasCar: true)
                                : _draft.copyWith(hasCar: true);
                          }),
                        ),
                        _QuickChip(
                          label: 'עבודה מהבית',
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

                    // ── Minimum income ──────────────────────────────────────
                    _sectionTitle('הכנסה חודשית (מינימום)',
                        IconsaxPlusLinear.wallet_money),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final v in const [8000.0, 12000.0, 16000.0, 20000.0])
                          _QuickChip(
                            label: '${_fmt(v.toInt())}+',
                            selected: _draft.incomeMin == v,
                            onTap: () => setState(() {
                              _draft = _draft.incomeMin == v
                                  ? _draft.copyWith(clearIncomeMin: true)
                                  : _draft.copyWith(incomeMin: v);
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Verified only ───────────────────────────────────────
                    _sectionTitle('אימות פרופיל', IconsaxPlusLinear.shield_tick),
                    const SizedBox(height: 12),
                    Wrap(
                      children: [
                        _QuickChip(
                          label: 'מאומת בלבד',
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
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(_draft),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navy,
                      side: const BorderSide(color: AppColors.borderLight),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('החל'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Toggles membership of [key] in the [field] set ('occupation' | 'household')
  /// and stores the updated set on the draft.
  void _toggleSet(String field, String key) {
    final current =
        field == 'occupation' ? _draft.occupation : _draft.household;
    final next = Set<String>.from(current);
    if (next.contains(key)) {
      next.remove(key);
    } else {
      next.add(key);
    }
    setState(() {
      _draft = field == 'occupation'
          ? _draft.copyWith(occupation: next)
          : _draft.copyWith(household: next);
    });
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

/// Occupation keys → Hebrew label, matching the tenant profile / eligibility
/// vocabulary so a liker's stored key renders and filters correctly.
const Map<String, String> _kOccupationLabels = <String, String>{
  'hightech': 'הייטק',
  'healthcare': 'בריאות/רפואה',
  'education': 'חינוך/הוראה',
  'finance': 'פיננסים/בנקאות',
  'law': 'משפטים',
  'engineering': 'הנדסה',
  'selfemployed': 'עצמאי/ת',
  'public': 'שירות ציבורי',
  'retail': 'מסחר/שירות',
  'academia': 'אקדמיה',
  'student': 'סטודנט/ית',
  'other': 'אחר',
};

const Map<String, String> _kHouseholdLabels = <String, String>{
  'family': 'משפחה',
  'single': 'רווק/ה',
  'couple': 'זוג',
  'student': 'סטודנט/ית',
};

String _occupationLabel(String key) => _kOccupationLabels[key] ?? key;

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
