import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/add_property_screen.dart'
    show AddPropertyScreen, EditPropertyScreen;
import 'package:dating_app/presentation/screens/message_screen.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

class LandlordDashboardScreen extends StatelessWidget {
  const LandlordDashboardScreen({
    super.key,
    required this.onOpenSwipes,
    required this.onOpenMatches,
    required this.onOpenProperties,
  });

  final VoidCallback onOpenSwipes;
  final VoidCallback onOpenMatches;
  final VoidCallback onOpenProperties;

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final stats = provider.landlordStats;
        final profile = provider.tenantProfile;
        final landlordName = profile?.name ?? 'בעל הדירה';
        final photoUrl = profile?.photoUrl ?? '';
        final matches = provider.matches.take(3).toList();
        final properties = provider.myProperties;
        final heroMedia = _landlordHeroMedia(properties);
        final pendingCount = stats.pendingCount;
        final unseenCount = provider.unseenMatchCount;

        if (provider.isLoading) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
                child: CircularProgressIndicator(color: AppColors.primary)),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Collapsible hero ─────────────────────────────────────
              SliverAppBar(
                automaticallyImplyLeading: false,
                expandedHeight: 220,
                pinned: true,
                stretch: true,
                backgroundColor: const Color(0xFF06243A),
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.parallax,
                  background: _HeroBackground(
                    name: landlordName,
                    photoUrl: photoUrl,
                    heroMedia: heroMedia,
                    stats: stats,
                    pendingCount: pendingCount,
                    unseenCount: unseenCount,
                  ),
                ),
              ),

              // ── Main content ─────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Pipeline visualizer
                    _PipelineCard(
                      leadsCount: provider.ownerLeads.length,
                      matchesCount: stats.matchesCount,
                      propertiesCount: stats.propertiesCount,
                      onLeads: onOpenSwipes,
                      onMatches: onOpenMatches,
                    ),
                    const SizedBox(height: 20),

                    // Quick actions
                    _QuickActionsGrid(
                      pendingCount: pendingCount,
                      unseenCount: unseenCount,
                      onAddProperty: () =>
                          _push(context, const AddPropertyScreen()),
                      onSwipes: onOpenSwipes,
                      onMatches: onOpenMatches,
                      onProperties: onOpenProperties,
                    ),
                    const SizedBox(height: 20),

                    // Activity feed
                    _ActivitySection(
                      provider: provider,
                      context: context,
                      onOpenSwipes: onOpenSwipes,
                      onOpenMatches: onOpenMatches,
                    ),
                    const SizedBox(height: 20),

                    // Recent matches
                    if (matches.isNotEmpty) ...[
                      _SectionHeader(
                        title: 'התאמות פעילות',
                        subtitle: 'שיחות שמצפות לטיפול',
                        onSeeAll: onOpenMatches,
                      ),
                      const SizedBox(height: 12),
                      ...matches.map(
                        (m) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _MatchRow(
                            match: m,
                            provider: provider,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // My properties preview
                    if (properties.isNotEmpty) ...[
                      _SectionHeader(
                        title: 'הנכסים שלי',
                        subtitle: '${properties.length} נכסים פעילים',
                        onSeeAll: onOpenProperties,
                      ),
                      const SizedBox(height: 12),
                      _PropertiesScroll(
                        properties: properties,
                        provider: provider,
                        context: context,
                      ),
                    ] else ...[
                      _EmptyPropertiesCard(
                        onAdd: () => _push(context, const AddPropertyScreen()),
                      ),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

// ─── Hero Background ──────────────────────────────────────────────────────────

class _HeroBackground extends StatelessWidget {
  const _HeroBackground({
    required this.name,
    required this.photoUrl,
    required this.heroMedia,
    required this.stats,
    required this.pendingCount,
    required this.unseenCount,
  });

  final String name;
  final String photoUrl;
  final PropertyMedia? heroMedia;
  final LandlordStats stats;
  final int pendingCount;
  final int unseenCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _LandlordHeroBackdrop(heroMedia: heroMedia),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF06243A).withValues(alpha: 0.46),
                const Color(0xFF06243A).withValues(alpha: 0.84),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ProfileAvatar(photoUrl: photoUrl, name: name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'שלום, $name 👋',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          pendingCount > 0
                              ? '$pendingCount מועמדים מחכים לאישור'
                              : 'הכל תחת שליטה',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (unseenCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(IconsaxPlusBold.message,
                              size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            '$unseenCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const Spacer(),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _HeroStatPill(
                      label: '${stats.propertiesCount} דירות',
                      icon: IconsaxPlusBold.building,
                    ),
                    const SizedBox(width: 8),
                    _HeroStatPill(
                      label: '${stats.pendingCount} ממתינים',
                      icon: IconsaxPlusBold.profile_2user,
                      highlight: pendingCount > 0,
                    ),
                    const SizedBox(width: 8),
                    _HeroStatPill(
                      label: '${stats.matchesCount} מאצ\'ים',
                      icon: IconsaxPlusBold.heart,
                    ),
                    const SizedBox(width: 8),
                    _HeroStatPill(
                      label: '${stats.conversionRate.round()}% המרה',
                      icon: IconsaxPlusBold.chart_2,
                    ),
                  ],
                ),
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

class _LandlordHeroBackdrop extends StatelessWidget {
  const _LandlordHeroBackdrop({required this.heroMedia});

  final PropertyMedia? heroMedia;

  @override
  Widget build(BuildContext context) {
    if (heroMedia != null) {
      return SafeMedia(
        media: heroMedia!,
        fit: BoxFit.cover,
        fallback: const _HeroBackdropFallback(),
        videoMode: SafeVideoDisplayMode.playback,
      );
    }
    return const _HeroBackdropFallback();
  }
}

class _HeroBackdropFallback extends StatelessWidget {
  const _HeroBackdropFallback();

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
            top: -24,
            right: -18,
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
            bottom: -40,
            left: -16,
            child: Container(
              width: 180,
              height: 180,
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

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.photoUrl, required this.name});
  final String photoUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isNotEmpty
        ? name
            .trim()
            .split(' ')
            .map((w) => w.isEmpty ? '' : w[0])
            .take(2)
            .join()
        : '?';
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Always-visible initials layer
            _InitialsCircle(initials: initials),
            // Photo on top — only when URL is available
            if (photoUrl.isNotEmpty)
              Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
}

class _InitialsCircle extends StatelessWidget {
  const _InitialsCircle({required this.initials});
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
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _HeroStatPill extends StatelessWidget {
  const _HeroStatPill({
    required this.label,
    required this.icon,
    this.highlight = false,
  });

  final String label;
  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0xFFFFD166).withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: highlight
            ? Border.all(color: const Color(0xFFFFD166).withValues(alpha: 0.5))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 12,
              color: highlight
                  ? const Color(0xFFFFD166)
                  : Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: highlight
                  ? const Color(0xFFFFD166)
                  : Colors.white.withValues(alpha: 0.85),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pipeline Card ────────────────────────────────────────────────────────────

class _PipelineCard extends StatelessWidget {
  const _PipelineCard({
    required this.leadsCount,
    required this.matchesCount,
    required this.propertiesCount,
    required this.onLeads,
    required this.onMatches,
  });

  final int leadsCount;
  final int matchesCount;
  final int propertiesCount;
  final VoidCallback onLeads;
  final VoidCallback onMatches;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 20, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(IconsaxPlusBold.chart_2, size: 16, color: AppColors.primary),
              SizedBox(width: 7),
              Text(
                'משפך שכירות',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Pipeline flow
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {},
                    child: _PipelineStage(
                      label: 'נכסים',
                      count: propertiesCount,
                      icon: IconsaxPlusBold.building,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                _PipelineArrow(),
                Expanded(
                  child: GestureDetector(
                    onTap: onLeads,
                    child: _PipelineStage(
                      label: 'לידים',
                      count: leadsCount,
                      icon: IconsaxPlusBold.profile_2user,
                      color: AppColors.primary,
                      tappable: true,
                    ),
                  ),
                ),
                _PipelineArrow(),
                Expanded(
                  child: GestureDetector(
                    onTap: onMatches,
                    child: _PipelineStage(
                      label: "מאצ'ים",
                      count: matchesCount,
                      icon: IconsaxPlusBold.heart,
                      color: AppColors.coral,
                      tappable: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Progress bar
          _PipelineProgressBar(
            leads: leadsCount,
            matches: matchesCount,
          ),
        ],
      ),
    );
  }
}

class _PipelineStage extends StatelessWidget {
  const _PipelineStage({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    this.tappable = false,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final bool tappable;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border:
            tappable ? Border.all(color: color.withValues(alpha: 0.2)) : null,
      ),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (tappable)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'צפה',
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Icon(IconsaxPlusBold.arrow_left, size: 10, color: color),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PipelineArrow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Icon(
        IconsaxPlusBold.arrow_left,
        size: 18,
        color: AppColors.borderLight,
      ),
    );
  }
}

class _PipelineProgressBar extends StatelessWidget {
  const _PipelineProgressBar({required this.leads, required this.matches});
  final int leads;
  final int matches;

  @override
  Widget build(BuildContext context) {
    final convRate = leads == 0 ? 0.0 : (matches / leads).clamp(0.0, 1.0);
    final label = leads == 0
        ? 'אין לידים פעילים עדיין'
        : '${(convRate * 100).round()}% מהלידים הפכו למאצ\'ים';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'יחס המרה',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 11,
                fontWeight: FontWeight.w800,
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
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

// ─── Quick Actions Grid ───────────────────────────────────────────────────────

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid({
    required this.pendingCount,
    required this.unseenCount,
    required this.onAddProperty,
    required this.onSwipes,
    required this.onMatches,
    required this.onProperties,
  });

  final int pendingCount;
  final int unseenCount;
  final VoidCallback onAddProperty;
  final VoidCallback onSwipes;
  final VoidCallback onMatches;
  final VoidCallback onProperties;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'פעולות מהירות',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _QABtn(
                label: 'הוסף דירה',
                icon: IconsaxPlusBold.add_square,
                color: AppColors.primary,
                onTap: onAddProperty,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QABtn(
                label: 'מועמדים',
                icon: IconsaxPlusBold.profile_2user,
                badge: pendingCount,
                color: AppColors.navy,
                onTap: onSwipes,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QABtn(
                label: "מאצ'ים",
                icon: IconsaxPlusBold.heart,
                badge: unseenCount,
                color: AppColors.coral,
                onTap: onMatches,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QABtn(
                label: 'הנכסים',
                icon: IconsaxPlusBold.buildings_2,
                color: AppColors.success,
                onTap: onProperties,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QABtn extends StatelessWidget {
  const _QABtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.badge = 0,
    this.color = AppColors.primary,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final int badge;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 17),
                ),
                if (badge > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: color == AppColors.coral
                            ? AppColors.navy
                            : AppColors.coral,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          badge > 9 ? '9+' : '$badge',
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
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Activity Feed ────────────────────────────────────────────────────────────

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({
    required this.provider,
    required this.context,
    required this.onOpenSwipes,
    required this.onOpenMatches,
  });
  final DatingProvider provider;
  final BuildContext context;
  final VoidCallback onOpenSwipes;
  final VoidCallback onOpenMatches;

  List<_ActivityItem> _buildItems() {
    final items = <_ActivityItem>[];
    final leads = provider.ownerLeads;
    final unseen = provider.unseenMatchCount;
    final props = provider.myProperties;

    if (leads.isNotEmpty) {
      items.add(_ActivityItem(
        icon: IconsaxPlusBold.profile_2user,
        color: AppColors.primary,
        title:
            '${leads.length} ${leads.length == 1 ? 'שוכר מעוניין' : 'שוכרים מעוניינים'} בנכסים שלך',
        subtitle: 'ממתינים לאישור — ככל שתגיב מהר יותר, כך טוב יותר',
        cta: 'לסוויפ',
        onTap: onOpenSwipes,
      ));
    }

    if (unseen > 0) {
      items.add(_ActivityItem(
        icon: IconsaxPlusBold.message,
        color: AppColors.coral,
        title: '$unseen הודעות שלא נקראו',
        subtitle: 'שוכרים שכבר אישרת ממתינים לתגובה שלך',
        cta: 'לשיחות',
        onTap: onOpenMatches,
      ));
    }

    if (props.isEmpty) {
      items.add(_ActivityItem(
        icon: IconsaxPlusBold.add_square,
        color: AppColors.primary,
        title: 'הוסף את הנכס הראשון שלך',
        subtitle: 'נכסים עם תמונות מקבלים פי 3 יותר פניות',
        cta: 'הוסף',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddPropertyScreen()),
        ),
      ));
    } else {
      items.add(_ActivityItem(
        icon: IconsaxPlusBold.chart_2,
        color: AppColors.navy,
        title: 'פרופיל הנכסים שלך פעיל ומוצג לשוכרים',
        subtitle:
            '${props.length} ${props.length == 1 ? 'נכס' : 'נכסים'} פעילים — הוסף תמונות לשיפור הסיכויים',
        cta: null,
        onTap: null,
      ));
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildItems();
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'מה קורה עכשיו',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: const [
              BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 16,
                  offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            children: items.asMap().entries.map((e) {
              final isLast = e.key == items.length - 1;
              return _ActivityRow(item: e.value, isLast: isLast);
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _ActivityItem {
  const _ActivityItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? cta;
  final VoidCallback? onTap;
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item, required this.isLast});
  final _ActivityItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(item.icon, color: item.color, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (item.cta != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      item.cta!,
                      style: TextStyle(
                        color: item.color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ] else
                  Icon(IconsaxPlusBold.arrow_left,
                      size: 14,
                      color: AppColors.textSecondary.withValues(alpha: 0.4)),
              ],
            ),
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 70,
            color: AppColors.borderLight.withValues(alpha: 0.6),
          ),
      ],
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.onSeeAll,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: Row(
              children: [
                const Text(
                  'הכל',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Icon(IconsaxPlusBold.arrow_left,
                    size: 13, color: AppColors.primary),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Match Row ────────────────────────────────────────────────────────────────

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match, required this.provider});
  final RentalMatch match;
  final DatingProvider provider;

  @override
  Widget build(BuildContext context) {
    final property = provider.propertyById(match.propertyId);
    if (property == null) return const SizedBox.shrink();
    final lastMsg = match.messages.isNotEmpty ? match.messages.last.text : null;
    final status = _status(match);

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MessageScreen(matchId: match.id)),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 56,
                height: 56,
                child: property.media.isNotEmpty
                    ? SafeMedia(
                        media: property.media.first,
                        fallback: Container(
                          color: AppColors.primaryLight2,
                          child: const Center(
                            child: Icon(IconsaxPlusBold.building,
                                color: AppColors.primary, size: 22),
                          ),
                        ),
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      )
                    : Container(
                        color: AppColors.primaryLight2,
                        child: const Center(
                          child: Icon(IconsaxPlusBold.building,
                              color: AppColors.primary, size: 22),
                        ),
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
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusBadge(label: status.label, color: status.color),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    lastMsg ?? 'שיחה חדשה ממתינה',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'פתח',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ({String label, Color color}) _status(RentalMatch m) {
    if (m.ownerSigned && m.tenantSigned) {
      return (label: 'מאומת', color: const Color(0xFF1B9C6A));
    }
    if (m.contractSent) {
      return (label: 'חוזה נשלח', color: AppColors.primary);
    }
    if (m.messages.length >= 3) {
      return (label: 'פעיל', color: AppColors.navy);
    }
    return (label: 'ממתין', color: AppColors.textSecondary);
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }
}

// ─── Properties Preview ───────────────────────────────────────────────────────

class _PropertiesScroll extends StatelessWidget {
  const _PropertiesScroll({
    required this.properties,
    required this.provider,
    required this.context,
  });
  final List<RentalProperty> properties;
  final DatingProvider provider;
  final BuildContext context;

  @override
  Widget build(BuildContext outerContext) {
    return SizedBox(
      height: 188,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: properties.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _PropertyMiniCard(
          property: properties[i],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EditPropertyScreen(property: properties[i]),
            ),
          ),
        ),
      ),
    );
  }
}

class _PropertyMiniCard extends StatelessWidget {
  const _PropertyMiniCard({required this.property, required this.onTap});
  final RentalProperty property;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final media = property.media.isNotEmpty ? property.media.first : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              SizedBox(
                height: 86,
                child: media != null
                    ? SafeMedia(
                        media: media,
                        fallback: Container(
                          color: AppColors.navy,
                          child: const Center(
                            child: Icon(IconsaxPlusBold.building,
                                color: Colors.white30, size: 32),
                          ),
                        ),
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      )
                    : Container(
                        color: AppColors.navy.withValues(alpha: 0.8),
                        child: const Center(
                          child: Icon(IconsaxPlusBold.building,
                              color: Colors.white30, size: 32),
                        ),
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
                      property.city.isNotEmpty
                          ? property.city
                          : property.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${property.priceLabel} • ${property.roomsLabel} ח\'',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'פעיל',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
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

// ─── Empty properties ─────────────────────────────────────────────────────────

class _EmptyPropertiesCard extends StatelessWidget {
  const _EmptyPropertiesCard({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onAdd,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.25),
              style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(IconsaxPlusBold.add_square,
                  color: AppColors.primary, size: 26),
            ),
            const SizedBox(height: 12),
            const Text(
              'הוסף את הנכס הראשון שלך',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'פרסם דירה עכשיו וקבל פניות משוכרים מתאימים',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _PropertyQuickActionsSheet extends StatelessWidget {
  const _PropertyQuickActionsSheet({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            property.address,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          _SheetTile(
            icon: IconsaxPlusBold.edit,
            label: 'ערוך פרטי הנכס',
            color: AppColors.primary,
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EditPropertyScreen(property: property),
              ));
            },
          ),
          _SheetTile(
            icon: IconsaxPlusBold.trash,
            label: 'הסר נכס מהרשימה',
            color: AppColors.coral,
            onTap: () async {
              Navigator.pop(context);
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22)),
                  title: const Text('הסרת נכס',
                      style: TextStyle(
                          color: AppColors.navy, fontWeight: FontWeight.w900)),
                  content: const Text('האם אתה בטוח שברצונך להסיר נכס זה?',
                      style: TextStyle(color: AppColors.textSecondary)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('ביטול',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.coral),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('הסר'),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                await context
                    .read<DatingProvider>()
                    .removeLandlordProperty(property.id);
              }
            },
          ),
          _SheetTile(
            icon: IconsaxPlusBold.share,
            label: 'שתף קישור לנכס',
            color: AppColors.navy,
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('שיתוף בקרוב...')),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color:
                    color == AppColors.coral ? AppColors.coral : AppColors.navy,
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
              ),
            ),
            const Spacer(),
            const Icon(IconsaxPlusBold.arrow_left,
                size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
