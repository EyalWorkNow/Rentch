import 'dart:ui';
import 'package:dating_app/core/ui/platform_fx.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/gamification_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/widgets/safe_image.dart';
import 'package:dating_app/presentation/widgets/scale_bounce.dart';
import 'package:dating_app/presentation/widgets/fade_slide_entrance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/data/models/profile_tags.dart';

/// Tenant (apartment-seeker) profile detail — restyled to be visually
/// indistinguishable in polish from [PropertyDetailScreen]'s rentlyClassic
/// look: padded rounded hero card, key-stats fact grid, section cards with
/// teal icon + extrabold title + divider, chip wraps, and a frosted bottom
/// action bar. All original data (name, budget, rooms, move-in, trust, bio,
/// tags, liked property, reviews) is preserved; deal-breakers + a match
/// indicator are added to mirror the property page's section structure.
class TenantDetailScreen extends StatefulWidget {
  const TenantDetailScreen({
    super.key,
    required this.tenant,
    required this.property,
    required this.reviews,
  });

  final TenantProfile tenant;
  final RentalProperty property;
  final List<AppReview> reviews;

  @override
  State<TenantDetailScreen> createState() => _TenantDetailScreenState();
}

// ─── Shared style tokens (mirrored from property_detail_screen.dart) ──────────
const Color _kInk = AppColors.ink;
const Color _kMuted = AppColors.slate500;
const Color _kSlate = AppColors.slate700;
const Color _kSlate2 = AppColors.slate600;
const Color _kBorder = AppColors.slate200;
const Color _kFill = AppColors.slate50;
Color get _kTeal => AppColors.primary;

class _TenantDetailScreenState extends State<TenantDetailScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

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

  String _avgRating(List<AppReview> reviews) {
    if (reviews.isEmpty) return '0.0';
    final avg = reviews.fold(0, (s, r) => s + r.rating) / reviews.length;
    return avg.toStringAsFixed(1);
  }

  String get _roomsLabel {
    final r = widget.tenant.desiredRooms;
    return r.toStringAsFixed(r % 1 == 0 ? 0 : 1);
  }

  /// Real trust score for this candidate (no fabricated number).
  int get _trustScore =>
      GamificationService.computeTrustScore(widget.tenant, widget.reviews);

  /// Accept ("אהבתי · צור קשר") or reject ("דלג") the candidate by driving the
  /// same owner-swipe path the explore screen uses. We locate this candidate's
  /// property inside the landlord's pending leads and apply a right (accept) or
  /// left (reject) swipe — accepting creates the match/contact thread.
  Future<void> _resolveLead(bool accept) async {
    final provider = context.read<DatingProvider>();
    final leads = provider.ownerLeads;
    final index = leads.indexWhere((p) => p.id == widget.property.id);
    if (index >= 0) {
      await provider.handleOwnerSwipe(
        index,
        null,
        accept ? CardSwiperDirection.right : CardSwiperDirection.left,
        l10n: AppLocalizations.of(context)!,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tenant = widget.tenant;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ─── Hero: framed "window" photo card — identical treatment to
              // the property-detail page (white 8px frame + soft shadow). ─────
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    5,
                    MediaQuery.of(context).padding.top + 12,
                    5,
                    16,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: Colors.white, width: 8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: SizedBox(
                        height: 460,
                        child: _PhotoHero(
                          tenant: tenant,
                          controller: _pageController,
                          currentPage: _currentPage,
                          rating: _avgRating(widget.reviews),
                          roomsLabel: _roomsLabel,
                          onPageChanged: (i) =>
                              setState(() => _currentPage = i),
                          onBackTap: () => Navigator.of(context).pop(),
                        ),
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
                      // Name + verified subtitle (Mockup title block)
                      Text(
                        tenant.name,
                        style: const TextStyle(
                          color: _kInk,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          RentlyIcon(
                            IconsaxPlusLinear.verify,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l10n.tenantDetailScreenE45aa6fe,
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // ─── Key stats fact grid ────────────────────────────
                      Text(
                        l10n.tenantDetailScreen54b54821,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: _kInk,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _TenantFactsCard(
                        tenant: tenant,
                        budgetLabel: _fmt(tenant.budgetMax),
                        roomsLabel: _roomsLabel,
                        trustScore: _trustScore,
                      ),
                      const SizedBox(height: 24),

                      // ─── Match insight ──────────────────────────────────
                      _SectionCardShell(
                        title: l10n.tenantDetailScreenDc721374,
                        icon: IconsaxPlusLinear.flash_1,
                        child: _MatchInsightCard(
                          tenant: tenant,
                          property: widget.property,
                        ),
                      ),

                      // ─── Liked property ─────────────────────────────────
                      _SectionCardShell(
                        title: l10n.tenantDetailScreen342759aa,
                        icon: IconsaxPlusLinear.home_2,
                        child: _LikedPropertyDetailedCard(
                          property: widget.property,
                        ),
                      ),

                      // ─── About / bio ────────────────────────────────────
                      if (tenant.bio.isNotEmpty)
                        _SectionCardShell(
                          title: l10n.tenantDetailScreenAede4a6e,
                          icon: IconsaxPlusLinear.user,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _kFill,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _kBorder),
                            ),
                            child: Text(
                              tenant.bio,
                              style: const TextStyle(
                                color: _kSlate2,
                                fontSize: 14.5,
                                height: 1.55,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),

                      // ─── Important details / tags ───────────────────────
                      if (tenant.importantDetails.isNotEmpty)
                        _SectionCardShell(
                          title: l10n.tenantDetailScreen64680a66,
                          icon: IconsaxPlusLinear.flash_1,
                          child: _ChipWrap(
                            tags: tenant.importantDetails,
                          ),
                        ),

                      // ─── Deal-breakers ──────────────────────────────────
                      if (tenant.dealBreakers.isNotEmpty)
                        _SectionCardShell(
                          title: l10n.tenantDetailScreen64967671,
                          icon: IconsaxPlusLinear.warning_2,
                          child: _ChipWrap(
                            tags: tenant.dealBreakers,
                            danger: true,
                          ),
                        ),

                      // ─── Reviews ────────────────────────────────────────
                      if (widget.reviews.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n.tenantDetailScreen6987e12c,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: _kInk,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.yellowPale.withValues(alpha: 0.3),
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
                                    _avgRating(widget.reviews),
                                    style: const TextStyle(
                                      color: AppColors.amberDeep,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _HorizontalTenantReviews(reviews: widget.reviews),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ─── Frosted bottom action bar ──────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _TenantBottomBar(
              onReject: () => _resolveLead(false),
              onAccept: () => _resolveLead(true),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Photo hero (mirrors _ImageGallery treatment) ────────────────────────────

class _PhotoHero extends StatelessWidget {
  const _PhotoHero({
    required this.tenant,
    required this.controller,
    required this.currentPage,
    required this.rating,
    required this.roomsLabel,
    required this.onPageChanged,
    required this.onBackTap,
  });

  final TenantProfile tenant;
  final PageController controller;
  final int currentPage;
  final String rating;
  final String roomsLabel;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onBackTap;

  @override
  Widget build(BuildContext context) {
    final photos = tenant.photoUrls;
    final safeCurrent =
        photos.isEmpty ? 0 : currentPage.clamp(0, photos.length - 1).toInt();

    return Stack(
      fit: StackFit.expand,
      children: [
        photos.isEmpty
            ? const _AvatarFallback()
            : PageView.builder(
                controller: controller,
                onPageChanged: onPageChanged,
                itemCount: photos.length,
                itemBuilder: (_, i) => SafeImage(
                  source: photos[i],
                  fit: BoxFit.cover,
                  fallback: const _AvatarFallback(),
                ),
              ),

        // Bottom dark gradient for text readability
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 160,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.black.withValues(alpha: 0.4),
                    Colors.black.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Top controls: back button + rating capsule
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ScaleBounce(
                onTap: onBackTap,
                scaleDownTo: 0.88,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const RentlyIcon(
                    IconsaxPlusLinear.arrow_right_3,
                    color: _kInk,
                    size: 20,
                  ),
                ),
              ),
              if (rating != '0.0')
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const RentlyIcon(
                        IconsaxPlusLinear.star_1,
                        size: 14,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        rating,
                        style: const TextStyle(
                          color: _kInk,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // Bottom overlay: seeker badge + key line
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
                  color: _kTeal.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kTeal.withValues(alpha: 0.3)),
                ),
                child: Text(
                  AppLocalizations.of(context)!.tenantDetailScreenB4cc85ed,
                  style: TextStyle(
                    color: _kTeal,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                AppLocalizations.of(context)!
                    .tenantDetailScreen548d9521(roomsLabel, tenant.moveInWindow),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),

        // Carousel dots
        if (photos.length > 1)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: _CarouselDots(count: photos.length, current: safeCurrent),
            ),
          ),
      ],
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy,
      child: const Center(
        child: RentlyIcon(
          IconsaxPlusLinear.profile_circle,
          size: 88,
          color: Colors.white24,
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

// ─── Section card shell (mirrors property page primitive) ────────────────────

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
            Icon(icon, color: _kTeal, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: _kInk,
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

// ─── Tenant key-stats fact grid (mirrors _PropertyFactsCard) ─────────────────

class _TenantFactsCard extends StatelessWidget {
  const _TenantFactsCard({
    required this.tenant,
    required this.budgetLabel,
    required this.roomsLabel,
    required this.trustScore,
  });

  final TenantProfile tenant;
  final String budgetLabel;
  final String roomsLabel;
  final int trustScore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                  IconsaxPlusLinear.wallet,
                  budgetLabel,
                  l10n.tenantDetailScreen0ee38ad3,
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
                  IconsaxPlusLinear.building,
                  roomsLabel,
                  l10n.tenantDetailScreenB50b3974,
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
                delay: const Duration(milliseconds: 120),
                duration: const Duration(milliseconds: 400),
                offset: const Offset(0.0, 25.0),
                child: _FactItemCard(
                  IconsaxPlusLinear.calendar,
                  tenant.moveInWindow,
                  l10n.tenantDetailScreen1399cd87,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: FadeSlideEntrance(
                delay: const Duration(milliseconds: 180),
                duration: const Duration(milliseconds: 400),
                offset: const Offset(0.0, 25.0),
                child: _FactItemCard(
                  IconsaxPlusLinear.shield_tick,
                  '$trustScore',
                  l10n.tenantDetailScreenC7f6f4e8,
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
  const _FactItemCard(this.icon, this.value, this.label);

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: _kMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
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
              color: _kMuted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── Chip wrap (mirrors _FeatureWrap / _DarkCapsuleTag) ──────────────────────

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.tags, this.danger = false});
  final List<String> tags;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final iconColor = danger ? AppColors.coral : _kTeal;
    final fill = danger ? AppColors.coral.withValues(alpha: 0.06) : _kFill;
    final border =
        danger ? AppColors.coral.withValues(alpha: 0.25) : _kBorder;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tags.map((raw) {
        final tag = ProfileTagCatalog.tagFor(raw, isLandlord: false);
        final t = tag?.displayLabel(l10n) ?? raw;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                danger
                    ? IconsaxPlusLinear.warning_2
                    : IconsaxPlusLinear.tick_circle,
                size: 15,
                color: iconColor,
              ),
              const SizedBox(width: 8),
              Text(
                t,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: danger ? AppColors.coral : _kSlate,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── Match insight (mirrors property page _MatchInsightCard layout) ──────────

class _MatchInsightCard extends StatelessWidget {
  _MatchInsightCard({required this.tenant, required this.property});
  final TenantProfile tenant;
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final reasons = _buildReasons(l10n);
    final score = _score();
    final (fg, bg) = _tierColors(score);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Center(
                child: Text(
                  '$score',
                  style: TextStyle(
                      color: fg, fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tierLabel(l10n, score),
                    style: TextStyle(
                        color: fg, fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  Text(
                    l10n.tenantDetailScreen0333a357,
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (final r in reasons)
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
                  child: Icon(r.$1, size: 14, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    r.$2,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.check_circle_rounded,
                    size: 16, color: AppColors.green),
              ],
            ),
          ),
      ],
    );
  }

  // Real budget/rooms fit against THIS property (not fabricated claims).
  bool get _budgetFits =>
      tenant.budgetMax > 0 && tenant.budgetMax >= property.price;
  bool get _roomsFit =>
      tenant.desiredRooms > 0 &&
      (tenant.desiredRooms - property.rooms).abs() <= 0.5;

  List<(IconData, String)> _buildReasons(AppLocalizations l10n) {
    final reasons = <(IconData, String)>[];
    final roomsText = tenant.desiredRooms
        .toStringAsFixed(tenant.desiredRooms % 1 == 0 ? 0 : 1);
    // Budget — state the real relationship to THIS property's rent.
    if (tenant.budgetMax > 0) {
      reasons.add((
        IconsaxPlusLinear.money_recive,
        _budgetFits
            ? l10n.tenantDetailScreen9bf902f4(tenant.budgetMax, property.price)
            : l10n.tenantDetailScreenDe6e13c4(tenant.budgetMax, property.price),
      ));
    }
    // Rooms — real comparison to the property.
    if (tenant.desiredRooms > 0) {
      reasons.add((
        IconsaxPlusLinear.home_2,
        _roomsFit
            ? l10n.tenantDetailScreen1e958c2f(roomsText, property.roomsLabel)
            : l10n.tenantDetailScreenB8e3e192(roomsText, property.roomsLabel),
      ));
    }
    if (tenant.moveInWindow.isNotEmpty) {
      reasons.add((
        IconsaxPlusLinear.calendar_1,
        l10n.tenantDetailScreen12c58e28(tenant.moveInWindow),
      ));
    }
    if (tenant.importantDetails.isNotEmpty) {
      final detailLabels = tenant.importantDetails.take(2).map((raw) {
        final tag = ProfileTagCatalog.tagFor(raw, isLandlord: false);
        return tag?.displayLabel(l10n) ?? raw;
      }).join(', ');
      reasons.add((
        IconsaxPlusLinear.flash_1,
        l10n.tenantDetailScreenE3b82a80(detailLabels),
      ));
    }
    return reasons.take(4).toList();
  }

  // A REAL fit score: the two hard rental constraints (budget covers rent,
  // rooms match) drive it, plus a small bump for a fuller, no-deal-breaker
  // profile. So a tenant whose budget is under the rent no longer scores high.
  int _score() {
    var s = 40;
    if (_budgetFits) s += 30;
    if (_roomsFit) s += 20;
    if (tenant.dealBreakers.isEmpty) s += 5;
    if (tenant.bio.isNotEmpty || tenant.importantDetails.isNotEmpty) s += 5;
    return s.clamp(0, 99);
  }

  String _tierLabel(AppLocalizations l10n, int score) {
    if (score >= 90) return l10n.tenantDetailScreen0e27d010;
    if (score >= 80) return l10n.tenantDetailScreen716b886b;
    if (score >= 70) return l10n.tenantDetailScreenAb92611a;
    return l10n.tenantDetailScreen758f13a3;
  }

  (Color, Color) _tierColors(int score) {
    if (score >= 90) {
      return (AppColors.green, AppColors.border);
    }
    if (score >= 80) return (AppColors.primary, AppColors.primaryLight2);
    if (score >= 70) {
      return (AppColors.blue, AppColors.border);
    }
    return (AppColors.amberDark, AppColors.warningBg);
  }
}

// ─── Liked property card (kept from original, restyled to match) ─────────────

class _LikedPropertyDetailedCard extends StatelessWidget {
  _LikedPropertyDetailedCard({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    final image = property.imageUrl;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (image.isNotEmpty)
              SizedBox(
                height: 140,
                width: double.infinity,
                child: SafeImage(
                  source: image,
                  fit: BoxFit.cover,
                  fallback: Container(
                    color: AppColors.navy,
                    child: const Center(
                      child: RentlyIcon(
                        IconsaxPlusLinear.building,
                        size: 40,
                        color: Colors.white24,
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          property.propertyType,
                          style: TextStyle(
                            color: _kTeal,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          property.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _kInk,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const RentlyIcon(
                              IconsaxPlusLinear.building,
                              size: 13,
                              color: _kMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              AppLocalizations.of(context)!
                                  .tenantDetailScreenD886d07f(
                                      property.roomsLabel),
                              style: const TextStyle(
                                color: _kMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const RentlyIcon(
                              IconsaxPlusLinear.maximize_3,
                              size: 13,
                              color: _kMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              AppLocalizations.of(context)!
                                  .tenantDetailScreenFdb4eac7(property.sizeM2),
                              style: const TextStyle(
                                color: _kMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          property.priceLabel,
                          style: const TextStyle(
                            color: _kInk,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          property.priceSuffixLabel,
                          style: const TextStyle(
                            color: _kMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
}

// ─── Horizontal reviews (mirrors _HorizontalReviewsList) ─────────────────────

class _HorizontalTenantReviews extends StatelessWidget {
  const _HorizontalTenantReviews({required this.reviews});
  final List<AppReview> reviews;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
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
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: _kBorder,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _kInk,
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
                              color: _kInk,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            AppLocalizations.of(context)!
                                .tenantDetailScreen6c58947e,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: _kMuted,
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
                      color: _kSlate2,
                    ),
                    maxLines: 4,
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

// ─── Frosted bottom action bar (mirrors property page _BottomBar) ────────────

class _TenantBottomBar extends StatelessWidget {
  const _TenantBottomBar({required this.onReject, required this.onAccept});
  final VoidCallback onReject;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(18), sigmaY: PlatformFx.blurSigma(18)),
        child: Container(
          padding: EdgeInsets.fromLTRB(
              20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            border: const Border(
              top: BorderSide(color: _kBorder, width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: ScaleBounce(
                  onTap: onReject,
                  scaleDownTo: 0.94,
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const RentlyIcon(IconsaxPlusLinear.close_circle,
                        size: 18),
                    label: Text(
                        AppLocalizations.of(context)!.tenantDetailScreen80a413c5,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kInk,
                      side: const BorderSide(color: _kBorder),
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
                child: ScaleBounce(
                  onTap: onAccept,
                  scaleDownTo: 0.95,
                  child: FilledButton.icon(
                    onPressed: onAccept,
                    icon: const RentlyIcon(IconsaxPlusLinear.heart, size: 18),
                    label: Text(
                      AppLocalizations.of(context)!.tenantDetailScreen96c6fb01,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _kTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
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
