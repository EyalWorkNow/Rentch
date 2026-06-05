import 'dart:io';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/google_auth_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/features/user/profile/edit_profile_screen.dart';
import 'package:dating_app/presentation/screens/add_property_screen.dart';
import 'package:dating_app/presentation/screens/auth_screen.dart';
import 'package:dating_app/presentation/screens/landlord_properties_screen.dart';
import 'package:dating_app/presentation/screens/matches_screen.dart';
import 'package:dating_app/presentation/screens/message_screen.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rentch_icon.dart';
import 'package:provider/provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('מחיקת חשבון',
            style:
                TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900)),
        content: const Text(
          'פעולה זו תמחק לצמיתות את החשבון ואת כל הנתונים שלך. לא ניתן לבטל פעולה זו.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('מחק חשבון'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;
    final provider = context.read<DatingProvider>();
    final navigator = Navigator.of(context);

    try {
      await GoogleAuthService().signOut();
    } catch (_) {}
    await provider.deleteAccount();

    if (!context.mounted) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('יציאה מהחשבון',
            style:
                TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900)),
        content: const Text(
          'האם אתה בטוח שברצונך לצאת?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.coral,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('יציאה'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;
    final provider = context.read<DatingProvider>();
    final navigator = Navigator.of(context);

    try {
      await GoogleAuthService().signOut();
    } catch (_) {}
    await provider.logout();

    if (!context.mounted) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final profile = provider.tenantProfile;
        if (provider.isLoading || profile == null) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
                child: CircularProgressIndicator(color: AppColors.primary)),
          );
        }

        if (provider.isLandlord) {
          return _LandlordProfileScreen(
            profile: profile,
            provider: provider,
            onLogout: () => _confirmLogout(context),
            onDeleteAccount: () => _confirmDeleteAccount(context),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFF1F5F9),
                  Color(0xFFF8FAFC),
                  Color(0xFFE6F9FB), // light teal instead of pink
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Bar Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'הפרופיל שלי',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const RentchIcon(
                                IconsaxPlusLinear.notification,
                                color: Color(0xFF0F172A),
                                size: 20,
                              ),
                              Positioned(
                                top: 12,
                                right: 12,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary, // App primary color instead of pink
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Avatar area (Mockup Style)
                    Center(
                      child: Column(
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              // Teal outer circle ring
                              Container(
                                width: 253,
                                height: 253,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.primary,
                                      AppColors.primary.withValues(alpha: 0.3),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                              ),
                              // White inner ring
                              Container(
                                width: 239,
                                height: 239,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              // Actual profile picture
                              ClipOval(
                                child: SizedBox(
                                  width: 220,
                                  height: 220,
                                  child: profile.photoUrl.isNotEmpty
                                      ? (profile.photoUrl.startsWith('/')
                                          ? Image.file(File(profile.photoUrl),
                                              fit: BoxFit.cover)
                                          : Image.network(profile.photoUrl,
                                              fit: BoxFit.cover))
                                      : Container(
                                          color: const Color(0xFFE2E8F0),
                                          child: const RentchIcon(
                                            IconsaxPlusLinear.user,
                                            size: 100,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                ),
                              ),
                              // Checked teal badge overlay
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary, // App primary color instead of pink
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 3.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.1),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                profile.name,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        EditProfileScreen(profile: profile),
                                  ),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: const RentchIcon(
                                    IconsaxPlusLinear.edit_2,
                                    size: 14,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'שוכר',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Profile Completion progress card (Mockup Style)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'שלמות הפרופיל שלי',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                '${provider.profileCompletion}%',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: provider.profileCompletion / 100,
                              minHeight: 10,
                              backgroundColor: const Color(0xFFF1F5F9),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Stats bar (Mockup Style individual boxes)
                    Row(
                      children: [
                        Expanded(
                          child: _MockupStatBox(
                            count: provider.likesCount.toString(),
                            label: 'אהבתי',
                            icon: IconsaxPlusBold.heart,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MockupStatBox(
                            count: provider.matchesCount.toString(),
                            label: 'התאמות',
                            icon: IconsaxPlusBold.messages_2,
                            color: AppColors.coral,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MockupStatBox(
                            count: provider.passedCount.toString(),
                            label: 'דילגתי',
                            icon: Icons.close_rounded,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Search Preferences Grouped Container
                    const Text(
                      'הגדרות',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _PreferenceTile(
                            icon: IconsaxPlusLinear.money,
                            label: 'תקציב מקסימלי',
                            value: _fmt(profile.budgetMax),
                          ),
                          const _SettingsDivider(),
                          _PreferenceTile(
                            icon: IconsaxPlusLinear.building,
                            label: 'מספר חדרים',
                            value: '${profile.desiredRooms} חדרים',
                          ),
                          const _SettingsDivider(),
                          _PreferenceTile(
                            icon: IconsaxPlusLinear.calendar,
                            label: 'מועד כניסה',
                            value: profile.moveInWindow,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // About me
                    if (profile.bio.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                RentchIcon(IconsaxPlusLinear.user,
                                    size: 18, color: Color(0xFF64748B)),
                                SizedBox(width: 8),
                                Text(
                                  'עליי',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              profile.bio,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF475569),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Actions Container
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          _ActionRow(
                            icon: IconsaxPlusLinear.logout,
                            label: 'יציאה מהחשבון',
                            onTap: () => _confirmLogout(context),
                            isDestructive: true,
                          ),
                          const _SettingsDivider(),
                          _ActionRow(
                            icon: IconsaxPlusLinear.trash,
                            label: 'מחיקת חשבון',
                            onTap: () => _confirmDeleteAccount(context),
                            isDestructive: true,
                          ),
                        ],
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

// ---------------------------------------------------------------------------
// Sliver header
// ---------------------------------------------------------------------------

class _ProfileSliverHeader extends StatefulWidget {
  const _ProfileSliverHeader({
    required this.profile,
    required this.profileCompletion,
    required this.onEdit,
  });

  final TenantProfile profile;
  final int profileCompletion;
  final VoidCallback onEdit;

  @override
  State<_ProfileSliverHeader> createState() => _ProfileSliverHeaderState();
}

class _ProfileSliverHeaderState extends State<_ProfileSliverHeader> {
  int _currentPage = 0;
  final _pageCtrl = PageController();

  @override
  void didUpdateWidget(covariant _ProfileSliverHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextPage = oldWidget.profile.id == widget.profile.id
        ? _safePhotoIndex(_currentPage)
        : 0;
    if (nextPage != _currentPage || oldWidget.profile.id != widget.profile.id) {
      _currentPage = nextPage;
      _jumpToCurrentPageAfterBuild();
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  int _safePhotoIndex(int index) {
    final photoCount = widget.profile.photoUrls.length;
    if (photoCount <= 0) return 0;
    return index.clamp(0, photoCount - 1).toInt();
  }

  void _jumpToCurrentPageAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageCtrl.hasClients) return;
      _pageCtrl.jumpToPage(_safePhotoIndex(_currentPage));
    });
  }

  /// Pick the first meaningful badge detail from importantDetails.
  String? _badgeDetail(List<String> details) {
    if (details.isEmpty) return null;
    return details.first;
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final photos = profile.photoUrls;
    final badge = _badgeDetail(profile.importantDetails);
    final safeCurrentPage = _safePhotoIndex(_currentPage);

    return SliverAppBar(
      expandedHeight: 340,
      pinned: false,
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
      title: const Text('הפרופיל שלי'),
      actions: [
        TextButton.icon(
          onPressed: widget.onEdit,
          icon: const RentchIcon(IconsaxPlusLinear.edit,
              color: Colors.white, size: 16),
          label: const Text(
            'עריכה',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          style: TextButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(width: 12),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Photo carousel (or fallback)
            photos.isEmpty
                ? Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.navy, Color(0xFF0D3D60)],
                      ),
                    ),
                  )
                : PageView.builder(
                    controller: _pageCtrl,
                    itemCount: photos.length,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    itemBuilder: (_, i) => _ProfileImageCell(url: photos[i]),
                  ),

            // Invisible tap zones for gallery navigation
            if (photos.length > 1)
              Positioned.fill(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () {
                            if (safeCurrentPage > 0) {
                              _pageCtrl.previousPage(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeInOut,
                              );
                            }
                          },
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () {
                            if (safeCurrentPage < photos.length - 1) {
                              _pageCtrl.nextPage(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeInOut,
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Gradient overlay
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xEE072946), Colors.transparent],
                    stops: [0.0, 0.65],
                  ),
                ),
              ),
            ),

            // Photo dots
            if (photos.length > 1)
              Positioned(
                bottom: 88,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(photos.length, (i) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: safeCurrentPage == i ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: safeCurrentPage == i
                              ? AppColors.primary
                              : Colors.white.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  ),
                ),
              ),

            // Name, avatar, budget
            Positioned(
              bottom: 20,
              right: 20,
              left: 20,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar with white border + completion mini chart
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                          child: CircleAvatar(
                            radius: 36,
                            backgroundColor: AppColors.primary,
                            backgroundImage: profile.photoUrl.isNotEmpty &&
                                    !profile.photoUrl.startsWith('/')
                                ? NetworkImage(profile.photoUrl)
                                : null,
                            foregroundImage: profile.photoUrl.startsWith('/')
                                ? FileImage(File(profile.photoUrl))
                                : null,
                            child: profile.photoUrl.isEmpty
                                ? const RentchIcon(
                                    IconsaxPlusLinear.profile_circle,
                                    color: Colors.white,
                                    size: 34)
                                : null,
                          ),
                        ),
                        if (widget.profileCompletion < 100)
                          Positioned(
                            bottom: -5,
                            left: -5,
                            child: _MiniCompletion(
                                percent: widget.profileCompletion),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      profile.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const RentchIcon(IconsaxPlusLinear.money,
                            size: 14, color: Colors.white60),
                        const SizedBox(width: 5),
                        Text(
                          'תקציב עד ${_fmt(profile.budgetMax)} • ${profile.desiredRooms} חדרים',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
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

// ---------------------------------------------------------------------------
// Profile image cell
// ---------------------------------------------------------------------------

class _ProfileImageCell extends StatelessWidget {
  const _ProfileImageCell({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _fallback();
    if (url.startsWith('/') || url.startsWith('file://')) {
      final path = url.startsWith('file://') ? url.substring(7) : url;
      return Image.file(File(path),
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback());
    }
    return Image.network(url,
        fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback());
  }

  Widget _fallback() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.navy, Color(0xFF0D3D60)],
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Stats bar
// ---------------------------------------------------------------------------

class _StatsBar extends StatelessWidget {
  const _StatsBar({
    required this.likes,
    required this.matches,
    required this.passed,
  });

  final int likes;
  final int matches;
  final int passed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _StatBarItem(
              icon: IconsaxPlusLinear.heart,
              color: AppColors.primary,
              value: likes.toString(),
              label: 'אהבתי',
              isFirst: true,
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: AppColors.borderLight,
            ),
            _StatBarItem(
              icon: IconsaxPlusLinear.message,
              color: const Color(0xFF4A6CF7),
              value: matches.toString(),
              label: 'התאמות',
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: AppColors.borderLight,
            ),
            _StatBarItem(
              icon: IconsaxPlusLinear.close_circle,
              color: AppColors.coral,
              value: passed.toString(),
              label: 'דילגתי',
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBarItem extends StatelessWidget {
  const _StatBarItem({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.isFirst = false,
    this.isLast = false,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.04),
          borderRadius: BorderRadius.horizontal(
            left: isLast ? const Radius.circular(20) : Radius.zero,
            right: isFirst ? const Radius.circular(20) : Radius.zero,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section card
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preference row
// ---------------------------------------------------------------------------

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Divider
// ---------------------------------------------------------------------------

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, thickness: 1, color: AppColors.borderLight);
  }
}

// ---------------------------------------------------------------------------
// Review card
// ---------------------------------------------------------------------------

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final AppReview review;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const RentchIcon(IconsaxPlusLinear.star_1,
                  color: Color(0xFFE8A84A), size: 15),
              const SizedBox(width: 5),
              Text(
                '${review.rating}/5',
                style: const TextStyle(
                    fontWeight: FontWeight.w900, color: AppColors.navy),
              ),
              const SizedBox(width: 8),
              Text(
                review.authorName,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            review.text,
            style: const TextStyle(
                color: AppColors.textSecondary, height: 1.4, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action tile
// ---------------------------------------------------------------------------

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppColors.coral : AppColors.navy;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: color,
                  ),
                ),
              ),
              RentchIcon(
                IconsaxPlusLinear.arrow_left,
                size: 16,
                color: AppColors.textSecondary.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mini completion chart
// ---------------------------------------------------------------------------

class _MiniCompletion extends StatelessWidget {
  const _MiniCompletion({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final color = percent >= 80
        ? const Color(0xFF27AE60)
        : percent >= 50
            ? AppColors.primary
            : const Color(0xFFF39C12);
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              value: percent / 100,
              strokeWidth: 3,
              backgroundColor: AppColors.borderLight,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Text(
            '$percent',
            style: const TextStyle(
              fontSize: 7,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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

// ===========================================================================
// LANDLORD PROFILE — full redesign
// ===========================================================================

class _LandlordProfileScreen extends StatelessWidget {
  const _LandlordProfileScreen({
    required this.profile,
    required this.provider,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  final TenantProfile profile;
  final DatingProvider provider;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}';
    return name.isNotEmpty ? name[0] : '?';
  }

  @override
  Widget build(BuildContext context) {
    final stats = provider.landlordStats;
    final properties = provider.myProperties;
    final matches = provider.matches;
    final heroMedia = _landlordHeroMedia(properties);
    final tenantName = profile.name.isNotEmpty ? profile.name : 'בעל דירה';
    final initials = _initials(tenantName);
    final cities = properties.map((p) => p.city).toSet().take(2).join(', ');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Hero ────────────────────────────────────────────────────────
          SliverAppBar(
            automaticallyImplyLeading: false,
            expandedHeight: 260,
            pinned: true,
            stretch: true,
            backgroundColor: const Color(0xFF06243A),
            surfaceTintColor: Colors.transparent,
            actions: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => EditProfileScreen(profile: profile)),
                  ),
                  icon: const RentchIcon(IconsaxPlusLinear.edit_2,
                      color: Colors.white, size: 15),
                  label: const Text('עריכה',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999)),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: _LandlordHero(
                profile: profile,
                initials: initials,
                cities: cities,
                propertiesCount: stats.propertiesCount,
                heroMedia: heroMedia,
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── KPI bar ────────────────────────────────────────────
                _LandlordKpiBar(stats: stats),
                const SizedBox(height: 20),

                // ── Properties ─────────────────────────────────────────
                _LandlordSectionHeader(
                  title: 'הנכסים שלי',
                  subtitle: '${properties.length} נכסים פעילים',
                  icon: IconsaxPlusLinear.buildings_2,
                  actionLabel: properties.isNotEmpty ? 'ניהול' : null,
                  onAction: properties.isNotEmpty
                      ? () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const LandlordPropertiesScreen()))
                      : null,
                ),
                const SizedBox(height: 12),
                _PropertiesHorizontalScroll(
                  properties: properties,
                  onAdd: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AddPropertyScreen())),
                  onTap: (p) => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => EditPropertyScreen(property: p))),
                ),
                const SizedBox(height: 20),

                // ── Active conversations ────────────────────────────────
                if (matches.isNotEmpty) ...[
                  _LandlordSectionHeader(
                    title: 'שיחות פעילות',
                    subtitle: '${matches.length} שיחות פתוחות',
                    icon: IconsaxPlusLinear.message,
                    actionLabel: 'הכל',
                    onAction: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const MatchesScreen())),
                  ),
                  const SizedBox(height: 12),
                  _MatchConversationList(
                    matches: matches.take(3).toList(),
                    provider: provider,
                    tenantName: tenantName,
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Performance card ────────────────────────────────────
                _PerformanceCard(stats: stats),
                const SizedBox(height: 20),

                // ── Settings ────────────────────────────────────────────
                _SettingsCard(
                  onEditProfile: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => EditProfileScreen(profile: profile)),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Account actions ─────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.borderLight),
                    boxShadow: const [
                      BoxShadow(
                          color: AppColors.shadow,
                          blurRadius: 12,
                          offset: Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    children: [
                      _ActionTile(
                        icon: IconsaxPlusLinear.logout,
                        label: 'יציאה מהחשבון',
                        isDestructive: true,
                        onTap: onLogout,
                      ),
                      const Divider(
                          height: 1, indent: 74, color: AppColors.borderLight),
                      _ActionTile(
                        icon: IconsaxPlusLinear.trash,
                        label: 'מחיקת חשבון',
                        isDestructive: true,
                        onTap: onDeleteAccount,
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero background ──────────────────────────────────────────────────────────

class _LandlordHero extends StatelessWidget {
  const _LandlordHero({
    required this.profile,
    required this.initials,
    required this.cities,
    required this.propertiesCount,
    required this.heroMedia,
  });

  final TenantProfile profile;
  final String initials;
  final String cities;
  final int propertiesCount;
  final PropertyMedia? heroMedia;

  @override
  Widget build(BuildContext context) {
    final photoUrl = profile.photoUrl;
    final tenantName = profile.name.isNotEmpty ? profile.name : 'בעל דירה';

    return Stack(
      fit: StackFit.expand,
      children: [
        _LandlordProfileHeroBackdrop(heroMedia: heroMedia),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF06243A).withValues(alpha: 0.42),
                const Color(0xFF06243A).withValues(alpha: 0.84),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 60, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: ClipOval(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _InitialsBubble(initials: initials),
                              if (photoUrl.isNotEmpty &&
                                  !photoUrl.startsWith('/'))
                                Image.network(
                                  photoUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                )
                              else if (photoUrl.startsWith('/'))
                                Image.file(
                                  File(photoUrl),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const RentchIcon(IconsaxPlusLinear.verify,
                              size: 13, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              tenantName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                height: 1.1,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _HeroPill(
                              icon: IconsaxPlusLinear.buildings_2,
                              label: 'בעל דירה',
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (cities.isNotEmpty)
                              _HeroPill(
                                icon: IconsaxPlusLinear.location,
                                label: cities,
                                color: Colors.white.withValues(alpha: 0.85),
                                bg: Colors.white.withValues(alpha: 0.12),
                              ),
                            _HeroPill(
                              icon: IconsaxPlusLinear.building,
                              label: '$propertiesCount נכסים פעילים בתיק',
                              color: Colors.white.withValues(alpha: 0.85),
                              bg: Colors.white.withValues(alpha: 0.12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

PropertyMedia? _landlordHeroMedia(List<RentalProperty> properties) {
  for (final property in properties) {
    final media = property.primaryMedia;
    if (media != null) return media;
  }
  return null;
}

class _LandlordProfileHeroBackdrop extends StatelessWidget {
  const _LandlordProfileHeroBackdrop({required this.heroMedia});

  final PropertyMedia? heroMedia;

  @override
  Widget build(BuildContext context) {
    if (heroMedia != null) {
      return SafeMedia(
        media: heroMedia!,
        fit: BoxFit.cover,
        fallback: const _LandlordProfileHeroFallback(),
        videoMode: SafeVideoDisplayMode.playback,
      );
    }
    return const _LandlordProfileHeroFallback();
  }
}

class _LandlordProfileHeroFallback extends StatelessWidget {
  const _LandlordProfileHeroFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF06243A), Color(0xFF0D3554)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -28,
            right: -12,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            bottom: -44,
            left: -18,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InitialsBubble extends StatelessWidget {
  const _InitialsBubble({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({
    required this.icon,
    required this.label,
    required this.color,
    this.bg,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color? bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg ?? color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// ── KPI bar ──────────────────────────────────────────────────────────────────

class _LandlordKpiBar extends StatelessWidget {
  const _LandlordKpiBar({required this.stats});
  final LandlordStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          _KpiCell(
            value: '${stats.propertiesCount}',
            label: 'דירות',
            icon: IconsaxPlusLinear.buildings_2,
            color: AppColors.primary,
            isFirst: true,
          ),
          _KpiSeparator(),
          _KpiCell(
            value: '${stats.matchesCount}',
            label: 'שיחות',
            icon: IconsaxPlusLinear.message,
            color: const Color(0xFF4A6CF7),
          ),
          _KpiSeparator(),
          _KpiCell(
            value: '${stats.conversionRate.round()}%',
            label: 'המרה',
            icon: IconsaxPlusLinear.chart_2,
            color: AppColors.success,
          ),
          _KpiSeparator(),
          _KpiCell(
            value: '${stats.pendingCount}',
            label: 'ממתינים',
            icon: IconsaxPlusLinear.profile_2user,
            color: stats.pendingCount > 0
                ? const Color(0xFFE67E22)
                : AppColors.textSecondary,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _KpiCell extends StatelessWidget {
  const _KpiCell({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.isFirst = false,
    this.isLast = false,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.04),
          borderRadius: BorderRadius.horizontal(
            right: isFirst ? const Radius.circular(22) : Radius.zero,
            left: isLast ? const Radius.circular(22) : Radius.zero,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 7),
            Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1.0)),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _KpiSeparator extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(vertical: 16),
        color: AppColors.borderLight,
      );
}

// ── Section header ────────────────────────────────────────────────────────────

class _LandlordSectionHeader extends StatelessWidget {
  const _LandlordSectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 17, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w900)),
              Text(subtitle,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          GestureDetector(
            onTap: onAction,
            child: Row(
              children: [
                Text(actionLabel!,
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                const RentchIcon(IconsaxPlusLinear.arrow_left,
                    size: 13, color: AppColors.primary),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Properties horizontal scroll ──────────────────────────────────────────────

class _PropertiesHorizontalScroll extends StatelessWidget {
  const _PropertiesHorizontalScroll({
    required this.properties,
    required this.onAdd,
    required this.onTap,
  });

  final List<RentalProperty> properties;
  final VoidCallback onAdd;
  final ValueChanged<RentalProperty> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 188,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: properties.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          if (i == properties.length) {
            return _AddPropertyCard(onTap: onAdd);
          }
          return _PropertyMiniTile(
            property: properties[i],
            onTap: () => onTap(properties[i]),
          );
        },
      ),
    );
  }
}

class _PropertyMiniTile extends StatelessWidget {
  const _PropertyMiniTile({required this.property, required this.onTap});
  final RentalProperty property;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final media = property.media.isNotEmpty ? property.media.first : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 138,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: const [
            BoxShadow(
                color: AppColors.shadow, blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              SizedBox(
                height: 88,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SafeMedia(
                      media: media,
                      fallback: Container(
                        color: AppColors.navy.withValues(alpha: 0.8),
                        child: const Center(
                          child: RentchIcon(IconsaxPlusLinear.building,
                              color: Colors.white30, size: 30),
                        ),
                      ),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                    // Price badge
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.navy.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          property.priceLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Details
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      property.city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${property.roomsLabel} חד׳ • ${property.sizeM2} מ"ר',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('פעיל',
                          style: TextStyle(
                              color: AppColors.success,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800)),
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

class _AddPropertyCard extends StatelessWidget {
  const _AddPropertyCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
              style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const RentchIcon(IconsaxPlusLinear.add_square,
                  color: AppColors.primary, size: 22),
            ),
            const SizedBox(height: 10),
            const Text(
              'הוסף\nדירה',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Match conversations list ──────────────────────────────────────────────────

class _MatchConversationList extends StatelessWidget {
  const _MatchConversationList({
    required this.matches,
    required this.provider,
    required this.tenantName,
  });

  final List<RentalMatch> matches;
  final DatingProvider provider;
  final String tenantName;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        children: matches.asMap().entries.map((entry) {
          final isLast = entry.key == matches.length - 1;
          return _ConversationRow(
            match: entry.value,
            provider: provider,
            tenantName: tenantName,
            isLast: isLast,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MessageScreen(matchId: entry.value.id))),
          );
        }).toList(),
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.match,
    required this.provider,
    required this.tenantName,
    required this.isLast,
    required this.onTap,
  });

  final RentalMatch match;
  final DatingProvider provider;
  final String tenantName;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final property = provider.propertyById(match.propertyId);
    if (property == null) return const SizedBox.shrink();

    final lastMsg = match.messages.isNotEmpty ? match.messages.last : null;
    final awaitingReply = lastMsg != null && lastMsg.sender == tenantName;
    final media = property.media.isNotEmpty ? property.media.first : null;

    Color stageColor;
    String stageLabel;
    if (match.ownerSigned && match.tenantSigned) {
      stageColor = AppColors.success;
      stageLabel = 'מאומת';
    } else if (match.contractSent) {
      stageColor = AppColors.primary;
      stageLabel = 'חוזה נשלח';
    } else {
      stageColor = AppColors.navy;
      stageLabel = 'שיחה פתוחה';
    }

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                // Property thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 54,
                    height: 54,
                    child: SafeMedia(
                      media: media,
                      fallback: Container(
                        color: AppColors.primaryLight2,
                        child: const Center(
                            child: RentchIcon(IconsaxPlusLinear.building,
                                color: AppColors.primary, size: 22)),
                      ),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              property.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: stageColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color: stageColor.withValues(alpha: 0.25)),
                            ),
                            child: Text(stageLabel,
                                style: TextStyle(
                                    color: stageColor,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (awaitingReply) ...[
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE67E22)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('ממתין לתגובתך',
                                  style: TextStyle(
                                      color: Color(0xFFE67E22),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900)),
                            ),
                          ],
                          Expanded(
                            child: Text(
                              lastMsg?.text ?? 'שיחה חדשה',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const RentchIcon(IconsaxPlusLinear.arrow_left,
                      size: 15, color: AppColors.primary),
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          const Divider(height: 1, indent: 80, color: AppColors.borderLight),
      ],
    );
  }
}

// ── Performance card ──────────────────────────────────────────────────────────

class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({required this.stats});
  final LandlordStats stats;

  @override
  Widget build(BuildContext context) {
    final convRate = (stats.conversionRate / 100).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const RentchIcon(IconsaxPlusLinear.chart_2,
                    size: 17, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              const Text('ביצועי החשבון',
                  style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 16),
          _PerformanceRow(
            label: 'מועמדים סה"כ',
            value: '${stats.totalCandidatesSeen}',
            icon: IconsaxPlusLinear.profile_2user,
            color: AppColors.navy,
          ),
          const SizedBox(height: 10),
          _PerformanceRow(
            label: 'שיחות פעילות',
            value: '${stats.matchesCount}',
            icon: IconsaxPlusLinear.message,
            color: const Color(0xFF4A6CF7),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('יחס המרה',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Flexible(
                child: Text(
                  '${stats.conversionRate.round()}% מהמועמדים הפכו לשיחות',
                  textAlign: TextAlign.left,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: convRate,
              backgroundColor: AppColors.borderLight,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              minHeight: 7,
            ),
          ),
        ],
      ),
    );
  }
}

class _PerformanceRow extends StatelessWidget {
  const _PerformanceRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 15, fontWeight: FontWeight.w900)),
      ],
    );
  }
}

// ── Settings card ────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.onEditProfile});
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          _SettingsTile(
            icon: IconsaxPlusLinear.user_edit,
            label: 'עריכת פרופיל',
            subtitle: 'שם, תמונה, פרטי קשר',
            color: AppColors.primary,
            onTap: onEditProfile,
          ),
          const Divider(height: 1, indent: 74, color: AppColors.borderLight),
          _SettingsTile(
            icon: IconsaxPlusLinear.notification,
            label: 'הגדרות התראות',
            subtitle: 'לידים, שיחות, התאמות',
            color: AppColors.navy,
            onTap: () {},
          ),
          const Divider(height: 1, indent: 74, color: AppColors.borderLight),
          _SettingsTile(
            icon: IconsaxPlusLinear.shield_tick,
            label: 'פרטיות ואבטחה',
            subtitle: 'ניהול הרשאות',
            color: const Color(0xFF4A6CF7),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            color: AppColors.navy)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              RentchIcon(IconsaxPlusLinear.arrow_left,
                  size: 16,
                  color: AppColors.textSecondary.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Redesigned helper widgets for Tenant Profile Screen
// ─────────────────────────────────────────────────────────────────────────────

class _MockupStatBox extends StatelessWidget {
  const _MockupStatBox({
    required this.count,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String count;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: RentchIcon(
              icon,
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            count,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: RentchIcon(
              icon,
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF475569),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const RentchIcon(
            IconsaxPlusLinear.arrow_left,
            size: 16,
            color: Color(0xFF94A3B8),
          ),
        ],
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: Color(0xFFE2E8F0),
      indent: 20,
      endIndent: 20,
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color =
        isDestructive ? AppColors.coral : const Color(0xFF0F172A);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDestructive
                    ? AppColors.coral.withValues(alpha: 0.1)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 20,
                color: color,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            RentchIcon(
              IconsaxPlusLinear.arrow_left,
              size: 16,
              color: isDestructive
                  ? AppColors.coral.withValues(alpha: 0.5)
                  : const Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }
}
