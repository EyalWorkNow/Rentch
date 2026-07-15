import 'dart:async';
import 'package:dating_app/core/ui/platform_fx.dart';
import 'dart:ui';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/features/onboarding/app_intro.dart';
import 'package:dating_app/presentation/features/search/search_chat_screen.dart';
import 'package:dating_app/presentation/screens/discover_screen.dart';
import 'package:dating_app/presentation/screens/explore_screen.dart';
import 'package:dating_app/presentation/screens/landlord_dashboard_screen.dart';
import 'package:dating_app/presentation/screens/landlord_properties_screen.dart';
import 'package:dating_app/presentation/screens/matches_screen.dart';
import 'package:dating_app/presentation/screens/profile_screen.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:dating_app/presentation/widgets/nav_assistant_orb.dart';
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

  // "דבר עם אתי" CTA: on every app entry the nav circle shows Etti's face for 2s,
  // then reverts to the icon — a gentle nudge toward the assistant.
  bool _ettiPeek = true;
  Timer? _ettiPeekTimer;

  static const int _landlordSwipesTabIndex = 1;
  static const int _landlordMatchesTabIndex = 2;
  static const int _landlordPropertiesTabIndex = 3;

  @override
  void initState() {
    super.initState();
    // First-run intro: after the first frame, show the "how to use" cards once.
    // Gated by the seen_intro_v1 flag inside AppIntro, so it only appears on a
    // genuine first launch and never blocks returning users.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowIntro());
    _ettiPeekTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _ettiPeek = false);
    });
  }

  @override
  void dispose() {
    _ettiPeekTimer?.cancel();
    super.dispose();
  }

  Future<void> _maybeShowIntro() async {
    if (_introChecked || !mounted) return;
    _introChecked = true;
    if (await AppIntro.hasBeenSeen()) return;
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
    final matchesIndex = provider.isLandlord ? 2 : 1;
    if (index == matchesIndex) {
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
                  onOpenSwipes: () => openLandlordTab(_landlordSwipesTabIndex),
                  onOpenMatches: () =>
                      openLandlordTab(_landlordMatchesTabIndex),
                  onOpenProperties: () =>
                      openLandlordTab(_landlordPropertiesTabIndex),
                ),
                const ExploreScreen(),
                const MatchesScreen(),
                const LandlordPropertiesScreen(),
                const ProfileScreen(),
              ]
            : const <Widget>[
                DiscoverScreen(),
                MatchesScreen(),
                SearchChatScreen(),
                ProfileScreen()
              ];

        final items = isLandlord ? _landlordItems : _tenantItems;
        final safeIndex = provider.currentTabIndex.clamp(0, screens.length - 1);
        final unseenCount = provider.unseenMatchCount;

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
              bottom: false,
              child: Padding(
                // Hug the bottom — a tight float above the home indicator. (Was 31;
                // the extra breathing room read as an empty "footer" strip below
                // the bar, which added nothing.)
                padding: const EdgeInsets.only(bottom: 12),
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
                            padding: EdgeInsets.all(safeIndex != 0 ? 9.0 : 8.0),
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
                                    index == (isLandlord ? 2 : 1) &&
                                        unseenCount > 0;
                                final isCompact = items.length >= 5;
                                final isNotDiscover = safeIndex != 0;
                                final double circleSize = isCompact
                                    ? (isNotDiscover ? 58.3 : 53.0)
                                    : (isNotDiscover ? 66.0 : 60.0);

                                return ScaleBounce(
                                  key: Key('nav_tab_$index'),
                                  onTap: () => _onTabTap(index, provider),
                                  scaleDownTo: 0.90,
                                  child: AnimatedContainer(
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
                                          : const Color(0xFF1A1A1A),
                                      // תכלת stroke marks ONLY the אתי CTA circle.
                                      border: isEtti
                                          ? Border.all(
                                              color: const Color(0xFF7CE0E6),
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
                                          _EttiCircleContent(
                                            showPhoto: isEtti &&
                                                (_ettiPeek || isSelected),
                                            size: circleSize,
                                            photo: ClipOval(
                                              child: Image.asset(
                                                'assets/images/eti.jpg',
                                                width: circleSize * 0.9,
                                                height: circleSize * 0.9,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                            fallback: isEtti
                                                // The voice-assistant orb — always
                                                // alive, colours drifting.
                                                ? NavAssistantOrb(
                                                    size: circleSize * 0.98)
                                                : AnimatedScale(
                                                    scale:
                                                        isSelected ? 1.12 : 1.0,
                                                    duration: const Duration(
                                                        milliseconds: 300),
                                                    curve: Curves.elasticOut,
                                                    child: RentlyIcon(
                                                      isSelected
                                                          ? item.activeIcon
                                                          : item.icon,
                                                      color: Colors.white,
                                                      size: isCompact
                                                          ? (isNotDiscover
                                                              ? 26.0
                                                              : 24.0)
                                                          : (isNotDiscover
                                                              ? 31.0
                                                              : 28.0),
                                                    ),
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

const _tenantItems = [
  _NavItem(
    label: 'גלה דירות',
    icon: IconsaxPlusLinear.building,
    activeIcon: IconsaxPlusLinear.building,
  ),
  _NavItem(
    label: 'התאמות',
    icon: IconsaxPlusLinear.message,
    activeIcon: IconsaxPlusLinear.message,
  ),
  _NavItem(
    label: 'דבר עם אתי',
    icon: IconsaxPlusLinear.search_normal_1,
    activeIcon: IconsaxPlusLinear.search_normal_1,
    isAssistant: true,
  ),
  _NavItem(
    label: 'פרופיל',
    icon: IconsaxPlusLinear.profile_circle,
    activeIcon: IconsaxPlusLinear.profile_circle,
  ),
];

const _landlordItems = [
  _NavItem(
    label: 'דשבורד',
    icon: IconsaxPlusLinear.category,
    activeIcon: IconsaxPlusLinear.category,
  ),
  _NavItem(
    label: 'סוויפים',
    icon: IconsaxPlusLinear.profile_2user,
    activeIcon: IconsaxPlusLinear.profile_2user,
  ),
  _NavItem(
    label: 'התאמות',
    icon: IconsaxPlusLinear.message,
    activeIcon: IconsaxPlusLinear.message,
  ),
  _NavItem(
    label: 'הדירות שלי',
    icon: IconsaxPlusLinear.buildings_2,
    activeIcon: IconsaxPlusLinear.buildings_2,
  ),
  _NavItem(
    label: 'פרופיל',
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
