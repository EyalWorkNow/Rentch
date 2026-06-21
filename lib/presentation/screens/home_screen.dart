import 'dart:ui';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/features/search/search_chat_screen.dart';
import 'package:dating_app/presentation/screens/discover_screen.dart';
import 'package:dating_app/presentation/screens/explore_screen.dart';
import 'package:dating_app/presentation/screens/landlord_dashboard_screen.dart';
import 'package:dating_app/presentation/screens/landlord_properties_screen.dart';
import 'package:dating_app/presentation/screens/matches_screen.dart';
import 'package:dating_app/presentation/screens/profile_screen.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:dating_app/presentation/widgets/scale_bounce.dart';
import 'package:flutter/material.dart';
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

  static const int _landlordSwipesTabIndex = 1;
  static const int _landlordMatchesTabIndex = 2;
  static const int _landlordPropertiesTabIndex = 3;

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
          body: RepaintBoundary(
            child: IndexedStack(
              key: ValueKey(isLandlord),
              index: safeIndex,
              children: screens,
            ),
          ),
          bottomNavigationBar: Theme(
            data: Theme.of(context).copyWith(
              canvasColor: Colors.transparent,
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
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
                          // 20 blur gives a premium liquid glass refraction
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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
                                          AnimatedScale(
                                            scale: isSelected ? 1.15 : 1.0,
                                            duration: const Duration(milliseconds: 300),
                                            curve: Curves.elasticOut,
                                            child: RentlyIcon(
                                              isSelected
                                                  ? item.activeIcon
                                                  : item.icon,
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
    label: 'חיפוש חכם',
    icon: IconsaxPlusLinear.search_normal_1,
    activeIcon: IconsaxPlusLinear.search_normal_1,
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
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}
