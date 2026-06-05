import 'dart:ui';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/discover_screen.dart';
import 'package:dating_app/presentation/screens/explore_screen.dart';
import 'package:dating_app/presentation/screens/landlord_dashboard_screen.dart';
import 'package:dating_app/presentation/screens/landlord_properties_screen.dart';
import 'package:dating_app/presentation/screens/matches_screen.dart';
import 'package:dating_app/presentation/screens/profile_screen.dart';
import 'package:dating_app/presentation/widgets/rentch_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
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
    setState(() => _currentIndex = index);
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

        if (_cachedIsLandlord != null && _cachedIsLandlord != isLandlord) {
          _currentIndex = 0;
        }
        _cachedIsLandlord = isLandlord;

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
                ProfileScreen()
              ];

        final items = isLandlord ? _landlordItems : _tenantItems;
        final safeIndex = _currentIndex.clamp(0, screens.length - 1);
        final unseenCount = provider.unseenMatchCount;

        const bool useGlass = true;

        return Scaffold(
          extendBody: true,
          body: IndexedStack(
            key: ValueKey(isLandlord),
            index: safeIndex,
            children: screens,
          ),
          bottomNavigationBar: Theme(
            data: Theme.of(context).copyWith(
              canvasColor: Colors.transparent,
            ),
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(useGlass ? 0.15 : 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: useGlass ? 60 : 0.001,
                          sigmaY: useGlass ? 60 : 0.001,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: useGlass
                                ? Colors.black.withValues(alpha: 0.35)
                                : Colors.black,
                            borderRadius: BorderRadius.circular(100),
                            border: useGlass
                                ? Border.all(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    width: 1.5)
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(items.length, (index) {
                              final item = items[index];
                              final isSelected = index == safeIndex;
                              final showBadge = index == (isLandlord ? 2 : 1) &&
                                  unseenCount > 0;
                              final isCompact = items.length >= 5;

                              final double circleSize = isCompact ? 62.0 : 70.0;

                              return GestureDetector(
                                onTap: () => _onTabTap(index, provider),
                                behavior: HitTestBehavior.opaque,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOutCubic,
                                  width: circleSize,
                                  height: circleSize,
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 1.0),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected
                                        ? AppColors.primary
                                        : const Color(0xFF1A1A1A),
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            RentchIcon(
                                              isSelected
                                                  ? item.activeIcon
                                                  : item.icon,
                                              color: Colors.white,
                                              size: isCompact ? 24 : 28,
                                            ),
                                            if (showBadge)
                                              Positioned(
                                                top: -4,
                                                right: -4,
                                                child: Container(
                                                  constraints:
                                                      const BoxConstraints(
                                                          minWidth: 16,
                                                          minHeight: 16),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 4),
                                                  decoration: const BoxDecoration(
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
                                          ],
                                        ),
                                        AnimatedSize(
                                          duration:
                                              const Duration(milliseconds: 250),
                                          curve: Curves.easeOutBack,
                                          child: isSelected
                                              ? Padding(
                                                  padding: const EdgeInsets.only(
                                                      top: 2.0),
                                                  child: Text(
                                                    item.label,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize:
                                                          isCompact ? 9 : 10.5,
                                                      fontWeight: FontWeight.w700,
                                                      height: 1.1,
                                                    ),
                                                  ),
                                                )
                                              : const SizedBox.shrink(),
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
