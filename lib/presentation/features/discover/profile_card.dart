import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:dating_app/presentation/widgets/property_share_sheet.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rentch_icon.dart';
import 'package:provider/provider.dart';

class ProfileCard extends StatefulWidget {
  const ProfileCard({
    super.key,
    required this.property,
    this.horizontalOffsetPercentage = 0,
  });

  final RentalProperty property;
  final int horizontalOffsetPercentage;

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard> {
  int _currentImage = 0;

  RentalProperty get p => widget.property;

  @override
  void didUpdateWidget(covariant ProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.property.id != widget.property.id) {
      _currentImage = 0;
      return;
    }
    _currentImage = _safeImageIndex(_currentImage);
  }

  int _safeImageIndex(int index) {
    final mediaLength = p.media.length;
    if (mediaLength <= 0) return 0;
    return index.clamp(0, mediaLength - 1).toInt();
  }

  void _prevImage() {
    final current = _safeImageIndex(_currentImage);
    if (current > 0) setState(() => _currentImage = current - 1);
  }

  void _nextImage() {
    final current = _safeImageIndex(_currentImage);
    if (current < p.media.length - 1) {
      setState(() => _currentImage = current + 1);
    }
  }

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailScreen(property: p),
      ),
    );
  }

  Future<void> _showSendOptions() async {
    HapticFeedback.selectionClick();
    await showPropertyShareSheet(context, p);
  }

  Future<void> _showMoreOptions(BuildContext context) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MoreOptionsSheet(property: p),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DatingProvider>();
    final isLiking = widget.horizontalOffsetPercentage > 10;
    final isPassing = widget.horizontalOffsetPercentage < -10;
    final media = p.media;
    final hasMultiple = media.length > 1;
    final safeCurrentImage = _safeImageIndex(_currentImage);
    final currentMedia = media.isNotEmpty ? media[safeCurrentImage] : null;
    final score = provider.matchScore(p);
    final priceCtx = provider.priceContext(p);
    final properties = provider.filteredProperties;
    final isGuest = provider.isGuestMode;
    final isFirst = isGuest && properties.isNotEmpty && p.id == properties.first.id;
    final isSecond = isGuest && properties.length > 1 && p.id == properties[1].id;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.16),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 18,
              spreadRadius: 2,
              offset: const Offset(0, 6),
            ),
            // Outward glass glow/reflection
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.08),
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
              // Background image — AnimatedSwitcher crossfades between images
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  fit: StackFit.expand,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                child: _CardImage(
                  key: ValueKey<String>(
                    '${p.id}:$safeCurrentImage:${currentMedia?.url ?? 'empty'}',
                  ),
                  media: currentMedia,
                  city: p.city,
                ),
              ),

              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.92),
                      Colors.black.withValues(alpha: 0.65),
                      Colors.black.withValues(alpha: 0.28),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.32, 0.60, 0.82],
                  ),
                ),
              ),

              // Image navigation tap zones (upper 55% of card)
              if (hasMultiple)
                Positioned.fill(
                  child: Column(
                    children: [
                      Expanded(
                        flex: 55,
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Row(
                            children: [
                              // Left tap -> prev
                              Expanded(
                                child: GestureDetector(
                                  onTap: _prevImage,
                                  behavior: HitTestBehavior.translucent,
                                  child: const SizedBox.expand(),
                                ),
                              ),
                              // Right tap -> next
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
                      const Expanded(flex: 45, child: SizedBox.shrink()),
                    ],
                  ),
                ),

              // Tap bottom area → detail page
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: MediaQuery.sizeOf(context).height * 0.28,
                child: GestureDetector(
                  onTap: () => _openDetail(context),
                  behavior: HitTestBehavior.translucent,
                ),
              ),

              // Progress bars — Stories-style image counter at very top
              if (hasMultiple)
                Positioned(
                  top: 12,
                  left: 14,
                  right: 14,
                  child: _ImageProgressBars(
                    count: media.length,
                    current: safeCurrentImage,
                  ),
                ),

              // Top row: agency badge + send/more buttons
              Positioned(
                top: hasMultiple ? 26 : 16,
                right: 16,
                left: 16,
                child: Row(
                  children: [
                    _AgencyBadge(agencyListing: p.agencyListing),
                    if (p.isVerifiedListing) ...[
                      const SizedBox(width: 8),
                      const _VerifiedListingBadge(),
                    ],
                    if (p.hasReadyVirtualTour) ...[
                      const SizedBox(width: 8),
                      const _TourReadyBadge(),
                    ],
                    const Spacer(),
                    GestureDetector(
                      onTap: _showSendOptions,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.42),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: const RentchIcon(
                          IconsaxPlusLinear.send_2,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _showMoreOptions(context),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.42),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: const Icon(
                          Icons.more_vert,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Swipe labels
              if (isLiking || isPassing)
                Positioned(
                  top: 28,
                  left: isPassing ? 22 : null,
                  right: isLiking ? 22 : null,
                  child: Transform.rotate(
                    angle: isLiking ? -0.15 : 0.15,
                    child: _SwipeBadge(
                      label: isLiking ? '♥ מתאים' : 'דלג',
                      color: isLiking ? AppColors.primary : AppColors.coral,
                    ),
                  ),
                ),
              // Content overlay (bottom layout directly on the dark gradient)
              Positioned(
                left: 16,
                right: 16,
                bottom: 128,
                child: GestureDetector(
                  onTap: () => _openDetail(context),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (priceCtx != PriceContext.average)
                            _PriceContextBadge(ctx: priceCtx)
                          else
                            const SizedBox.shrink(),
                          if (score > 0)
                            _MatchScoreBadge(score: score)
                          else
                            const SizedBox.shrink(),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            p.priceLabel,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            p.priceSuffixLabel,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          RentchIcon(
                            IconsaxPlusLinear.location,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              p.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            _StatPill(
                                icon: IconsaxPlusLinear.building,
                                label: '${p.roomsLabel} חדרים'),
                            const SizedBox(width: 6),
                            _StatPill(
                                icon: IconsaxPlusLinear.maximize_3,
                                label: '${p.sizeM2} מ"ר'),
                            if (p.floor.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              _StatPill(
                                  icon: IconsaxPlusLinear.layer,
                                  label: 'קומה ${p.floor}'),
                            ],
                            if (p.sizeM2 > 0) ...[
                              const SizedBox(width: 6),
                              _StatPill(
                                icon: IconsaxPlusLinear.moneys,
                                label: '₪${(p.price / p.sizeM2).round()}/מ"ר',
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
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

class _CardImage extends StatelessWidget {
  const _CardImage({super.key, required this.media, required this.city});
  final PropertyMedia? media;
  final String city;

  @override
  Widget build(BuildContext context) {
    final item = media;
    final fallback = _ImageFallback(city: city);
    if (item == null || item.url.trim().isEmpty) return fallback;

    return SafeMedia(
      media: item,
      fallback: fallback,
      fit: BoxFit.cover,
      alignment: Alignment.center,
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.city});
  final String city;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RentchIcon(
              IconsaxPlusLinear.building,
              size: 64,
              color: AppColors.primary.withValues(alpha: 0.5),
            ),
            if (city.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                city,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImageDots extends StatelessWidget {
  const _ImageDots({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const RentchIcon(IconsaxPlusLinear.gallery,
              size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            '${current + 1}/$count',
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _AgencyBadge extends StatelessWidget {
  const _AgencyBadge({required this.agencyListing});
  final bool agencyListing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            agencyListing
                ? IconsaxPlusLinear.verify
                : IconsaxPlusLinear.profile_circle,
            color: AppColors.primary,
            size: 13,
          ),
          const SizedBox(width: 5),
          Text(
            agencyListing ? 'תיווך מאומת' : 'בעלים פרטי',
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifiedListingBadge extends StatelessWidget {
  const _VerifiedListingBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF13BEC9).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(IconsaxPlusLinear.verify, color: Colors.white, size: 13),
          SizedBox(width: 5),
          Text(
            'מאומתת',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _TourReadyBadge extends StatelessWidget {
  const _TourReadyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.view_in_ar_rounded, color: Colors.white, size: 13),
          SizedBox(width: 5),
          Text(
            '3D',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeBadge extends StatelessWidget {
  const _SwipeBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 3),
        color: color.withValues(alpha: 0.08),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.label,
    this.highlight = false,
  });
  final IconData icon;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final bg = highlight
        ? AppColors.primary.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.12);
    final border = highlight
        ? AppColors.primary.withValues(alpha: 0.35)
        : Colors.white.withValues(alpha: 0.15);
    final iconColor = highlight ? AppColors.primary : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor.withValues(alpha: 0.5)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: highlight ? AppColors.primary : Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageProgressBars extends StatelessWidget {
  const _ImageProgressBars({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(count, (i) {
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: i <= current
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      }),
    );
  }
}

class _FeatureTag extends StatelessWidget {
  const _FeatureTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 1),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.primaryLight,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _MatchScoreBadge extends StatelessWidget {
  const _MatchScoreBadge({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 80
        ? const Color(0xFF10B981) // emerald
        : score >= 60
            ? const Color(0xFFF59E0B) // amber
            : AppColors.coral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RentchIcon(IconsaxPlusLinear.star_1, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            '$score% התאמה',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceContextBadge extends StatelessWidget {
  const _PriceContextBadge({required this.ctx});
  final PriceContext ctx;

  @override
  Widget build(BuildContext context) {
    if (ctx == PriceContext.average) return const SizedBox.shrink();
    final isBelow = ctx == PriceContext.belowAverage;
    final color = isBelow ? const Color(0xFF10B981) : AppColors.coral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Text(
        isBelow ? 'מחיר מעולה' : 'מחיר מעל הממוצע',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MoreOptionsSheet extends StatelessWidget {
  const _MoreOptionsSheet({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<DatingProvider>();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2B3A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          _OptionTile(
            icon: Icons.flag_outlined,
            label: 'דיווח על מודעה',
            onTap: () {
              Navigator.pop(context);
              _showReportDialog(context, provider);
            },
          ),
          const Divider(color: Colors.white12, height: 1),
          _OptionTile(
            icon: Icons.block,
            label: 'חסום משתמש זה',
            color: const Color(0xFFE74C3C),
            onTap: () {
              Navigator.pop(context);
              _showBlockConfirm(context, provider);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showReportDialog(BuildContext context, DatingProvider provider) {
    final reasons = [
      'מידע שגוי',
      'תמונות מזויפות',
      'תוכן פוגעני',
      'הונאה',
      'אחר',
    ];
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1C2B3A),
          title:
              const Text('סיבת הדיווח', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: reasons.map((reason) {
              return ListTile(
                title:
                    Text(reason, style: const TextStyle(color: Colors.white70)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await provider.reportProperty(property.id, reason);
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        duration: Duration(milliseconds: 2500),
                        content: Text('הדיווח נשלח. תודה.'),
                      ),
                    );
                  }
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showBlockConfirm(BuildContext context, DatingProvider provider) {
    final ownerName = property.ownerName;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1C2B3A),
          title:
              const Text('חסימת משתמש', style: TextStyle(color: Colors.white)),
          content: Text(
            'האם לחסום את "$ownerName"? כל המודעות שלהם יוסרו מהעדכון שלך.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('ביטול', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await provider.blockOwner(ownerName);
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      duration: const Duration(milliseconds: 2500),
                      content: Text('"$ownerName" נחסם בהצלחה.'),
                    ),
                  );
                }
              },
              child: const Text('חסום',
                  style: TextStyle(color: Color(0xFFE74C3C))),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(label,
          style: TextStyle(
              color: color, fontSize: 15, fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}
