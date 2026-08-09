import 'dart:async';
import 'dart:io' show Platform;
import 'package:dating_app/core/ui/platform_fx.dart';
import 'dart:ui';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/widgets/gamification/profile_completion_sheet.dart';
import 'package:dating_app/presentation/features/onboarding/app_intro.dart';
import 'package:dating_app/presentation/features/search/search_chat_screen.dart';
import 'package:dating_app/presentation/screens/discover_screen.dart';
import 'package:dating_app/presentation/screens/landlord_dashboard_screen.dart';
import 'package:dating_app/presentation/screens/leads_inbox_screen.dart';
import 'package:dating_app/presentation/screens/landlord_properties_screen.dart';
import 'package:dating_app/presentation/screens/matches_screen.dart';
import 'package:dating_app/presentation/screens/profile_screen.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';

import 'package:dating_app/presentation/widgets/scale_bounce.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:dating_app/presentation/widgets/animations/micro_animations.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool? _cachedIsLandlord;
  bool _introChecked = false;

  // The candidate deck + conversations are now merged into a single "לקוחות"
  // tab (LeadsInboxScreen) at index 1, so both the old swipes/matches deep-links
  // point there.
  static const int _landlordLeadsTabIndex = 1;
  static const int _landlordPropertiesTabIndex = 2;

  @override
  void initState() {
    super.initState();
    // First-run intro: after the first frame, show the "how to use" cards once.
    // Gated by the seen_intro_v1 flag inside AppIntro, so it only appears on a
    // genuine first launch and never blocks returning users.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowIntro());
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _maybeShowIntro() async {
    if (_introChecked || !mounted) return;
    _introChecked = true;
    if (!await AppIntro.hasBeenSeen()) {
      if (!mounted) return;
      await Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: true,
          pageBuilder: (_, __, ___) => AppIntro(
            onDone: () => Navigator.of(context).maybePop(),
          ),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    }
    // Tenant profile-completion nudge — pops once per launch when < 100%.
    // (The old first-launch subscription paywall was removed — landlords no
    // longer have a subscription; monetization is boost-only + broker upgrade.)
    if (mounted) {
      await ProfileCompletionSheet.maybeShow(context);
    }
  }

  void _showMatchOverlay(BuildContext context, RentalProperty property) {
    HapticFeedback.heavyImpact();
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        pageBuilder: (_, __, ___) =>
            MatchCelebrationOverlay(property: property),
      ),
    );
  }

  void _onTabTap(int index, DatingProvider provider) {
    HapticFeedback.selectionClick();
    provider.setTabIndex(index);
    // Tapping the apartment-search tab always lands on the swipe deck (not the
    // grid/map the user may have left it on).
    if (index == 0) {
      provider.requestDiscoverSwipes();
    }
    // Merged "לקוחות" tab (landlord) and "התאמות" tab (tenant) both live at
    // index 1, so opening index 1 marks conversations seen for either role.
    if (index == 1) {
      provider.markMatchesSeen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final isLandlord = provider.isLandlord;
        void openLandlordTab(int index) => _onTabTap(index, provider);

        // On a role change, reset to the first tab — but NEVER call
        // setTabIndex (which notifies listeners) during build. Doing so is the
        // classic "notifyListeners during build" trap: in release it can pin the
        // tab to 0 on every rebuild if the role ever flips (unstable async role
        // load), which presents exactly as "the navbar won't switch pages".
        // safeIndex clamping already prevents an out-of-range index, so this is
        // purely the reset UX and is safe to defer to after the frame.
        if (_cachedIsLandlord != null && _cachedIsLandlord != isLandlord) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) provider.setTabIndex(0);
          });
        }
        _cachedIsLandlord = isLandlord;

        // Keep the landlord's incoming likes fresh (throttled in the provider),
        // so a tenant's like shows up as a pending candidate without a relaunch.
        if (isLandlord) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              provider.refreshIncomingLikes();
              provider.refreshOwnedEngagement();
            }
          });
        }

        // Global match detection — works regardless of which tab is active.
        final pendingMatch = provider.pendingMatchProperty;
        if (pendingMatch != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            _showMatchOverlay(context, pendingMatch);
            provider.clearPendingMatch();
          });
        }

        final screens = isLandlord
            ? <Widget>[
                LandlordDashboardScreen(
                  // Candidates + conversations are one merged tab now, so both
                  // deep-links land on it (segment defaults to candidates).
                  onOpenSwipes: () => openLandlordTab(_landlordLeadsTabIndex),
                  onOpenMatches: () => openLandlordTab(_landlordLeadsTabIndex),
                  onOpenProperties: () =>
                      openLandlordTab(_landlordPropertiesTabIndex),
                ),
                const LeadsInboxScreen(),
                const LandlordPropertiesScreen(),
                const ProfileScreen(),
              ]
            : const <Widget>[
                DiscoverScreen(),
                MatchesScreen(),
                SearchChatScreen(),
                ProfileScreen()
              ];

        final l10n = AppLocalizations.of(context)!;
        final items =
            isLandlord ? _landlordItems(l10n) : _tenantItems(l10n);
        final safeIndex = provider.currentTabIndex.clamp(0, screens.length - 1);
        // The merged "לקוחות" tab (landlord, index 1) reflects BOTH pending
        // candidates and unread conversations; the tenant "התאמות" tab (also
        // index 1) reflects unread conversations only.
        final unseenCount = isLandlord
            ? provider.unseenMatchCount + provider.ownerLeads.length
            : provider.unseenMatchCount;

        return Scaffold(
          extendBody: true,
          // RepaintBoundary isolates the (often animating) body from the
          // bottomNavigationBar's BackdropFilter, so body frames don't force the
          // navbar to recomposite — keeps the bar responsive under load.
          body: Stack(
            children: [
              RepaintBoundary(
                child: IndexedStack(
                  key: ValueKey(isLandlord),
                  index: safeIndex,
                  children: screens,
                ),
              ),
              // Notifications now live inside the discover 3-dots menu (tenant)
              // and the dashboard header (landlord/agent), so no floating bell
              // is drawn over the deck here.
            ],
          ),
          bottomNavigationBar: Theme(
            data: Theme.of(context).copyWith(
              canvasColor: Colors.transparent,
            ),
            child: SafeArea(
              // Android: let SafeArea consume the REAL system-nav inset — works
              // for 3-button, gesture AND Samsung One UI, whatever its height —
              // so the floating bar always clears it (manual viewPadding math with
              // a hard cap was clipping Samsung's taller bar). iOS: keep
              // bottom:false for the tight 12px home-indicator float.
              bottom: Platform.isAndroid,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: Platform.isAndroid ? 10 : 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(100),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: BackdropFilter(
                          // 20 blur gives a premium liquid-glass refraction; on
                          // Android/Impeller this bar floats over the animating
                          // swipe deck and re-blurs the moving backdrop every
                          // frame, so trim it there via PlatformFx (iOS unchanged).
                          filter: ImageFilter.blur(
                              sigmaX: PlatformFx.blurSigma(20),
                              sigmaY: PlatformFx.blurSigma(20)),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                            padding: EdgeInsets.all(
                                (safeIndex != 0 ? 9.0 : 8.0) *
                                    (Platform.isAndroid ? 0.85 : 1.0)),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.black.withValues(alpha: 0.30),
                                  Colors.black.withValues(alpha: 0.15),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.24),
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(items.length, (index) {
                                final item = items[index];
                                final isSelected = index == safeIndex;
                                final isEtti = item.isAssistant;
                                final showBadge =
                                    index == 1 && unseenCount > 0;
                                // Profile tab: a progress ring around the circle
                                // showing how complete the tenant's profile is.
                                final profilePct = provider.profileCompletion;
                                final showCompletionRing = index == 3 &&
                                    !isLandlord &&
                                    profilePct > 0 &&
                                    profilePct < 100;
                                final isCompact = items.length >= 5;
                                final isNotDiscover = safeIndex != 0;
                                final double baseCircle = isCompact
                                    ? (isNotDiscover ? 58.3 : 53.0)
                                    : (isNotDiscover ? 66.0 : 60.0);
                                // Android: a touch smaller than iOS (iOS unchanged).
                                final double circleSize = Platform.isAndroid
                                    ? baseCircle * 0.9
                                    : baseCircle;

                                return ScaleBounce(
                                  key: Key('nav_tab_$index'),
                                  onTap: () => _onTabTap(index, provider),
                                  scaleDownTo: 0.90,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    clipBehavior: Clip.none,
                                    children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeOutCubic,
                                    width: circleSize,
                                    height: circleSize,
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 1.0),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.ink,
                                      // תכלת stroke marks ONLY the אתי CTA circle.
                                      border: isEtti
                                          ? Border.all(
                                              color: AppColors.primaryLight,
                                              width: 1.8)
                                          : null,
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: AppColors.primary.withValues(alpha: 0.45),
                                                blurRadius: 10,
                                                spreadRadius: 2,
                                              )
                                            ]
                                          : [],
                                    ),
                                    child: Center(
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          // אתי's circle: her PHOTO during the 3s
                                          // entry peek AND whenever her tab is active
                                          // (permanent on her page); an AI icon
                                          // otherwise. The photo RISES in with a
                                          // springy micro-animation.
                                          AnimatedScale(
                                            scale: isSelected ? 1.12 : 1.0,
                                            duration: const Duration(milliseconds: 300),
                                            curve: Curves.elasticOut,
                                            child: RentlyIcon(
                                              isSelected ? item.activeIcon : item.icon,
                                              color: Colors.white,
                                              size: isCompact
                                                  ? (isNotDiscover ? 26.0 : 24.0)
                                                  : (isNotDiscover ? 31.0 : 28.0),
                                            ),
                                          ),
                                          if (showBadge)
                                            Positioned(
                                              top: -4,
                                              right: -4,
                                              child: ScaleBopBadge(
                                                value: unseenCount,
                                                child: Container(
                                                  constraints:
                                                      const BoxConstraints(
                                                          minWidth: 16,
                                                          minHeight: 16),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 4),
                                                  decoration:
                                                      const BoxDecoration(
                                                    color: AppColors.coral,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      unseenCount > 9
                                                          ? '9+'
                                                          : '$unseenCount',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.w900,
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
                                  // Profile-completion ring hugging the circle.
                                  if (showCompletionRing)
                                    IgnorePointer(
                                      child: SizedBox(
                                        width: circleSize + 6,
                                        height: circleSize + 6,
                                        child: CircularProgressIndicator(
                                          value: profilePct / 100.0,
                                          strokeWidth: 2.6,
                                          backgroundColor:
                                              AppColors.ink.withValues(alpha: 0.25),
                                          valueColor:
                                              const AlwaysStoppedAnimation(
                                                  AppColors.superLike),
                                        ),
                                      ),
                                    ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

List<_NavItem> _tenantItems(AppLocalizations l10n) => [
      _NavItem(
        label: l10n.homeScreenFfcf1893,
        icon: IconsaxPlusLinear.search_normal,
        activeIcon: IconsaxPlusLinear.search_normal,
      ),
      _NavItem(
        label: l10n.homeScreen61f6102d,
        icon: IconsaxPlusLinear.message,
        activeIcon: IconsaxPlusLinear.message,
      ),
      _NavItem(
        label: l10n.homeScreenB2367383,
        icon: IconsaxPlusLinear.magic_star,
        activeIcon: IconsaxPlusBold.magic_star,
        isAssistant: true,
      ),
      _NavItem(
        label: l10n.homeScreenE1ea2811,
        icon: IconsaxPlusLinear.profile_circle,
        activeIcon: IconsaxPlusLinear.profile_circle,
      ),
    ];

List<_NavItem> _landlordItems(AppLocalizations l10n) => [
      _NavItem(
        label: l10n.homeScreen143fe31f,
        icon: IconsaxPlusLinear.category,
        activeIcon: IconsaxPlusLinear.category,
      ),
      _NavItem(
        label: l10n.homeScreen1881898b,
        icon: IconsaxPlusLinear.profile_2user,
        activeIcon: IconsaxPlusLinear.profile_2user,
      ),
      _NavItem(
        label: l10n.homeScreen2c577068,
        icon: IconsaxPlusLinear.buildings_2,
        activeIcon: IconsaxPlusLinear.buildings_2,
      ),
      _NavItem(
        label: l10n.homeScreenE1ea2811,
        icon: IconsaxPlusLinear.profile_circle,
        activeIcon: IconsaxPlusLinear.profile_circle,
      ),
    ];

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.isAssistant = false,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// The "דבר עם אתי" assistant tab — gets a label under the icon + the 2s avatar
  /// peek on entry.
  final bool isAssistant;
}

/// אתי's nav-circle content, in a FIXED-size box (so the transition never nudges
/// the rest of the navbar) and isolated in a RepaintBoundary (so the orb's
/// continuous repaint never re-blurs the whole glass bar → no flicker).
///
/// When [showPhoto] flips, her photo SPRINGS up from below (bouncy overshoot) and
/// the icon/orb sinks + fades — real physics via a SpringSimulation.
class _EttiCircleContent extends StatefulWidget {
  const _EttiCircleContent({
    required this.showPhoto,
    required this.size,
    required this.photo,
    required this.fallback,
  });

  final bool showPhoto;
  final double size;
  final Widget photo;
  final Widget fallback;

  @override
  State<_EttiCircleContent> createState() => _EttiCircleContentState();
}

class _EttiCircleContentState extends State<_EttiCircleContent>
    with SingleTickerProviderStateMixin {
  // 0 = fallback (orb/icon) shown, 1 = photo shown. Unbounded so the spring can
  // overshoot past 1 for a lively pop.
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
    value: widget.showPhoto ? 1.0 : 0.0,
  );

  static const _spring =
      SpringDescription(mass: 1.0, stiffness: 340, damping: 16);

  @override
  void didUpdateWidget(covariant _EttiCircleContent old) {
    super.didUpdateWidget(old);
    if (old.showPhoto != widget.showPhoto) {
      final target = widget.showPhoto ? 1.0 : 0.0;
      _c.animateWith(SpringSimulation(
          _spring, _c.value, target, (target - _c.value) * 5.5));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = _c.value;
            final photoV = t.clamp(0.0, 1.25); // may overshoot → a pop
            final fallV = (1.0 - t).clamp(0.0, 1.0);
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (fallV > 0.01)
                  Opacity(
                    opacity: fallV,
                    child: Transform.scale(
                      scale: 0.55 + 0.45 * fallV,
                      child: widget.fallback,
                    ),
                  ),
                if (photoV > 0.01)
                  Opacity(
                    opacity: photoV.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(
                          0, (1.0 - photoV.clamp(0.0, 1.0)) * widget.size * 0.5),
                      child: Transform.scale(
                        scale: photoV,
                        child: widget.photo,
                      ),
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
