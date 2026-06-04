import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/discover_screen.dart';
import 'package:dating_app/presentation/screens/explore_screen.dart';
import 'package:dating_app/presentation/screens/landlord_dashboard_screen.dart';
import 'package:dating_app/presentation/screens/landlord_properties_screen.dart';
import 'package:dating_app/presentation/screens/matches_screen.dart';
import 'package:dating_app/presentation/screens/profile_screen.dart';
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

        return Scaffold(
          extendBody: true,
          body: IndexedStack(
            key: ValueKey(isLandlord),
            index: safeIndex,
            children: screens,
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 28,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: List.generate(items.length, (index) {
                  final item = items[index];
                  final isSelected = index == safeIndex;
                  final showBadge =
                      index == (isLandlord ? 2 : 1) && unseenCount > 0;

                  final isCompact = items.length >= 5;
                  return Expanded(
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: isCompact ? 1 : 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _onTabTap(index, provider),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? 4 : 12, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : Colors.transparent,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Icon(
                                    isSelected ? item.activeIcon : item.icon,
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                    size: isCompact ? 20 : 22,
                                  ),
                                  if (showBadge)
                                    Positioned(
                                      top: -5,
                                      right: -6,
                                      child: Container(
                                        constraints: const BoxConstraints(
                                            minWidth: 16, minHeight: 16),
                                        padding: const EdgeInsets.symmetric(
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
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: TextStyle(
                                  fontSize: isCompact ? 9.5 : 11,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
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
    icon: IconsaxPlusBold.building,
    activeIcon: IconsaxPlusBold.building,
  ),
  _NavItem(
    label: 'התאמות',
    icon: IconsaxPlusBold.message,
    activeIcon: IconsaxPlusBold.message,
  ),
  _NavItem(
    label: 'פרופיל',
    icon: IconsaxPlusBold.profile_circle,
    activeIcon: IconsaxPlusBold.profile_circle,
  ),
];

const _landlordItems = [
  _NavItem(
    label: 'דשבורד',
    icon: IconsaxPlusBold.category,
    activeIcon: IconsaxPlusBold.category,
  ),
  _NavItem(
    label: 'סוויפים',
    icon: IconsaxPlusBold.profile_2user,
    activeIcon: IconsaxPlusBold.profile_2user,
  ),
  _NavItem(
    label: 'התאמות',
    icon: IconsaxPlusBold.message,
    activeIcon: IconsaxPlusBold.message,
  ),
  _NavItem(
    label: 'הדירות שלי',
    icon: IconsaxPlusBold.buildings_2,
    activeIcon: IconsaxPlusBold.buildings_2,
  ),
  _NavItem(
    label: 'פרופיל',
    icon: IconsaxPlusBold.profile_circle,
    activeIcon: IconsaxPlusBold.profile_circle,
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
