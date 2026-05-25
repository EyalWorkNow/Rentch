import 'dart:io';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/google_auth_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/features/user/profile/edit_profile_screen.dart';
import 'package:dating_app/presentation/screens/auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

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

        return Scaffold(
          backgroundColor: AppColors.background,
          body: CustomScrollView(
            slivers: [
              _ProfileSliverHeader(
                profile: profile,
                onEdit: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EditProfileScreen(profile: profile),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      // Stats row
                      Row(
                        children: [
                          _StatCard(
                            icon: IconsaxPlusBold.heart,
                            color: AppColors.primary,
                            value: provider.likesCount.toString(),
                            label: 'אהבתי',
                          ),
                          const SizedBox(width: 10),
                          _StatCard(
                            icon: IconsaxPlusBold.message,
                            color: const Color(0xFF4A6CF7),
                            value: provider.matchesCount.toString(),
                            label: 'התאמות',
                          ),
                          const SizedBox(width: 10),
                          _StatCard(
                            icon: IconsaxPlusBold.close_circle,
                            color: AppColors.coral,
                            value: provider.passedCount.toString(),
                            label: 'דילגתי',
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Search preferences
                      _SectionCard(
                        title: 'העדפות חיפוש',
                        icon: IconsaxPlusBold.search_normal,
                        child: Column(
                          children: [
                            _PreferenceRow(
                              icon: IconsaxPlusLinear.money,
                              label: 'תקציב מקסימלי',
                              value: _fmt(profile.budgetMax),
                            ),
                            const _Divider(),
                            _PreferenceRow(
                              icon: IconsaxPlusLinear.building,
                              label: 'מספר חדרים',
                              value: '${profile.desiredRooms} חדרים',
                            ),
                            const _Divider(),
                            _PreferenceRow(
                              icon: IconsaxPlusLinear.calendar,
                              label: 'מועד כניסה',
                              value: profile.moveInWindow,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // About me
                      if (profile.bio.isNotEmpty)
                        _SectionCard(
                          title: 'עליי',
                          icon: IconsaxPlusBold.user,
                          child: Text(
                            profile.bio,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                              height: 1.6,
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),
                      // Important details
                      if (profile.importantDetails.isNotEmpty)
                        _SectionCard(
                          title: 'פרטים לבעלי דירות',
                          icon: IconsaxPlusBold.info_circle,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: profile.importantDetails.map((d) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Text(
                                  d,
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      const SizedBox(height: 14),
                      // Reviews
                      if (provider.tenantReviews.isNotEmpty)
                        _SectionCard(
                          title: 'ביקורות',
                          icon: IconsaxPlusBold.star_1,
                          child: Column(
                            children: provider.tenantReviews
                                .take(3)
                                .map((r) => _ReviewCard(review: r))
                                .toList(),
                          ),
                        ),
                      const SizedBox(height: 14),
                      // Actions
                      _ActionTile(
                        icon: IconsaxPlusLinear.edit,
                        label: 'עריכת פרופיל',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EditProfileScreen(profile: profile),
                          ),
                        ),
                      ),
                      const SizedBox(height: 1),
                      _ActionTile(
                        icon: IconsaxPlusLinear.logout,
                        label: 'יציאה מהחשבון',
                        isDestructive: true,
                        onTap: () => _confirmLogout(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileSliverHeader extends StatefulWidget {
  const _ProfileSliverHeader({
    required this.profile,
    required this.onEdit,
  });

  final TenantProfile profile;
  final VoidCallback onEdit;

  @override
  State<_ProfileSliverHeader> createState() => _ProfileSliverHeaderState();
}

class _ProfileSliverHeaderState extends State<_ProfileSliverHeader> {
  int _currentPage = 0;
  final _pageCtrl = PageController();

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final photos = profile.photoUrls;

    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      automaticallyImplyLeading: false,
      backgroundColor: AppColors.navy,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
      title: const Text('הפרופיל שלי'),
      actions: [
        IconButton(
          icon: const Icon(IconsaxPlusLinear.edit, color: Colors.white),
          onPressed: widget.onEdit,
        ),
        const SizedBox(width: 4),
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
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () {
                          if (_currentPage > 0) {
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
                          if (_currentPage < photos.length - 1) {
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

            // Gradient overlay (wrapped in IgnorePointer)
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

            // Photo dots (wrapped in IgnorePointer)
            if (photos.length > 1)
              Positioned(
                bottom: 80,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(photos.length, (i) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: _currentPage == i ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _currentPage == i
                              ? AppColors.primary
                              : Colors.white.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  ),
                ),
              ),

            // Name and budget (wrapped in IgnorePointer)
            Positioned(
              bottom: 20,
              right: 20,
              left: 20,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar circle
                    CircleAvatar(
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
                          ? const Icon(IconsaxPlusBold.profile_circle,
                              color: Colors.white, size: 34)
                          : null,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      profile.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(IconsaxPlusLinear.money,
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: const [
            BoxShadow(
                color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 4))
          ],
        ),
        child: Column(
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
                fontSize: 22,
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
      padding: const EdgeInsets.all(16),
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
              Icon(icon, size: 17, color: AppColors.primary),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
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

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, thickness: 1, color: AppColors.borderLight);
  }
}

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
              const Icon(IconsaxPlusBold.star_1,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.borderLight),
        ),
        child: ListTile(
          leading: Icon(icon, color: color),
          title: Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
          trailing: const Icon(IconsaxPlusLinear.arrow_left,
              size: 18, color: AppColors.textSecondary),
          onTap: onTap,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
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
