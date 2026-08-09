import 'dart:math' as math;
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/features/calendar/availability_calendar_screen.dart';
import 'package:dating_app/data/models/availability_slot.dart';
import 'package:dating_app/data/repositories/availability_repository.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/features/assistant/erik_chat_screen.dart';
import 'package:dating_app/presentation/screens/notifications_screen.dart';
import 'package:dating_app/presentation/screens/rent_tracking_screen.dart';
import 'package:dating_app/presentation/features/tax/tax_helper_screen.dart';
import 'package:dating_app/presentation/features/landlord/reminders_screen.dart';
import 'package:dating_app/presentation/features/broker/area_intel_screen.dart';
import 'package:dating_app/presentation/features/broker/broker_tools_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/fade_slide_entrance.dart';
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
        final l10n = AppLocalizations.of(context)!;
        final stats = provider.landlordStats;
        final profile = provider.tenantProfile;
        final landlordName = profile?.name ?? l10n.landlordDashboardScreenC6c7d5f7;
        final photoUrl = profile?.photoUrl ?? '';
        final properties = provider.myProperties;
        
        // Calculate Expected Monthly Revenue — only ACTIVE RENTALS count as
        // ongoing monthly income. Sale listings hold a one-time asking price in
        // the same field, and paused/rented units aren't earning a new rent.
        final double expectedRevenue = properties
            .where((p) =>
                p.isActive &&
                p.transactionType == PropertyTransactionType.rent)
            .fold<double>(0.0, (sum, property) => sum + property.price);

        if (provider.isLoading) {
          return Scaffold(
            backgroundColor: AppColors.cloud,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.cloud,
          body: SafeArea(
            bottom: false,
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // ── Header ──
                FadeSlideEntrance(
                  delay: Duration.zero,
                  child: _DashboardHeader(
                    name: landlordName,
                    photoUrl: photoUrl,
                    pendingCount: stats.pendingCount,
                  ),
                ),
                const SizedBox(height: 24),

                // ── "System Performance" Styled Grid ──
                FadeSlideEntrance(
                  delay: const Duration(milliseconds: 80),
                  child: _SystemPerformanceGrid(
                    // Card unit is "פעילים" (active) — count only active listings,
                    // not paused/rented/draft ones.
                    propertiesCount: properties.where((p) => p.isActive).length,
                    expectedRevenue: expectedRevenue,
                    conversionRate: stats.conversionRate,
                    pendingCount: stats.pendingCount,
                  ),
                ),
                const SizedBox(height: 16),

                // ── My Calendar — prominent standalone card ──
                FadeSlideEntrance(
                  delay: const Duration(milliseconds: 120),
                  child: _CalendarCard(
                    onTap: () => _push(
                      context,
                      const AvailabilityCalendarScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Occupancy Arc Meter ──
                FadeSlideEntrance(
                  delay: const Duration(milliseconds: 160),
                  child: _OccupancyArcMeter(
                    // How many ACTIVE properties have at least one match —
                    // the label reads "נכסים עם התאמה / מתוך N נכסים פעילים",
                    // so both numerator and denominator are per-property (not
                    // total match count).
                    propertiesWithMatch: () {
                      final matchedIds =
                          provider.matches.map((m) => m.propertyId).toSet();
                      return properties
                          .where((p) =>
                              p.isActive && matchedIds.contains(p.id))
                          .length;
                    }(),
                    propertiesCount:
                        properties.where((p) => p.isActive).length,
                    expectedRevenue: expectedRevenue,
                  ),
                ),
                const SizedBox(height: 20),

                // ── Weekly Activity Bar Chart ──
                FadeSlideEntrance(
                  delay: const Duration(milliseconds: 240),
                  child: _WeeklyActivityChart(
                    properties: properties,
                    isGuest: provider.isGuestMode,
                  ),
                ),
                const SizedBox(height: 20),

                // ── Broker hub (מתווך only) — opens "כלי הסוכן" ──
                if (context.watch<DatingProvider>().isBroker) ...[
                  FadeSlideEntrance(
                    delay: const Duration(milliseconds: 340),
                    child: _BrokerToolsCard(),
                  ),
                  const SizedBox(height: 24),
                ],

                // ── Landlord Tools (big, plain-language helpers) ──
                FadeSlideEntrance(
                  delay: const Duration(milliseconds: 360),
                  child: _LandlordToolsSection(
                    properties: properties,
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        );
      },
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

// ─── Header Widget ──────────────────────────────────────────────────────────

class _DashboardHeader extends StatelessWidget {
  _DashboardHeader({
    required this.name,
    required this.photoUrl,
    required this.pendingCount,
  });

  final String name;
  final String photoUrl;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final firstName = name.split(' ').first;

    return Row(
      children: [
        // Left: Greeting text
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: l10n.landlordDashboardScreen235e6256,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextSpan(
                      text: '$firstName 👋',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                pendingCount > 0
                    ? l10n.landlordDashboardScreen9c8fa644(pendingCount)
                    : l10n.landlordDashboardScreen99884c14,
                style: TextStyle(
                  color: pendingCount > 0
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Right: Notification bell + Avatar
        Row(
          children: [
            // Real, working notifications bell (opens the inbox). Shown only
            // here on the agent/landlord dashboard — replaces the old fake icon.
            NotificationBell(
              onDeepLink: (n) {
                final provider = context.read<DatingProvider>();
                switch (n.type) {
                  case 'message':
                  case 'match':
                  case 'like':
                  case 'property_like':
                    provider.setTabIndex(1); // merged candidates + messages
                    provider.markMatchesSeen();
                  case 'tour':
                  case 'tour_ready':
                  case 'review':
                  case 'saved_search':
                    provider.setTabIndex(2); // my properties
                  default:
                    break;
                }
              },
            ),
            const SizedBox(width: 10),
            // Personal assistant ("עוזר אישי") — replaces the avatar. A clear
            // icon + tag opens Erik, the voice/text assistant built for older
            // landlords.
            // NOT const: its gradient is the swappable accent; a const widget
            // never rebuilds and would freeze on the first-build accent.
            _AssistantChip(),
          ],
        ),
      ],
    );
  }
}

class _AssistantChip extends StatelessWidget {
  // Non-const constructor on purpose: paints the swappable brand accent, so it
  // must be allowed to rebuild when the accent changes.
  _AssistantChip();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ErikChatScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 13, 8),
        decoration: AppColors.isBrokerAccent
            ? BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(100),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.30),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              )
            : BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(100),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.30),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(IconsaxPlusBold.microphone_2, color: Colors.white, size: 20),
            const SizedBox(width: 7),
            Text(
              l10n.landlordDashboardScreenCce14f4f,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── System Performance Grid ──────────────────────────────────────────────────

class _SystemPerformanceGrid extends StatelessWidget {
  const _SystemPerformanceGrid({
    required this.propertiesCount,
    required this.expectedRevenue,
    required this.conversionRate,
    required this.pendingCount,
  });

  final int propertiesCount;
  final double expectedRevenue;
  final double conversionRate;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.landlordDashboardScreen80293f4c,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: l10n.landlordDashboardScreen1b17721e,
                value: propertiesCount.toDouble(),
                unit: l10n.landlordDashboardScreen17127579,
                backgroundColor: Colors.white,
                isPrice: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: l10n.landlordDashboardScreen0b71fe76,
                value: expectedRevenue,
                unit: l10n.landlordDashboardScreen3ec09dc0,
                backgroundColor: Colors.white,
                isPrice: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _LargeProgressCard(
          title: l10n.landlordDashboardScreen94943464,
          progressValue: conversionRate / 100.0,
          conversionRate: conversionRate,
          statusText: pendingCount > 0
              ? l10n.landlordDashboardScreenEd3747d9(pendingCount)
              : l10n.landlordDashboardScreen8a106a06,
          icon: IconsaxPlusLinear.flash,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  _MetricCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.backgroundColor,
    this.isPrice = false,
  });

  final String title;
  final double value;
  final String unit;
  final Color backgroundColor;
  final bool isPrice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: value),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.easeOutCubic,
                  builder: (context, val, child) {
                    final displayValue = isPrice
                        ? '₪${val.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => "${m[1]},")}'
                        : val.toInt().toString();
                    return Text(
                      displayValue,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LargeProgressCard extends StatelessWidget {
  _LargeProgressCard({
    required this.title,
    required this.progressValue,
    required this.conversionRate,
    required this.statusText,
    required this.icon,
  });

  final String title;
  final double progressValue;
  final double conversionRate;
  final String statusText;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: progressValue),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      builder: (context, animatedProgress, _) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(
                    icon,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.bolt, color: AppColors.primary, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    statusText,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.0, end: conversionRate),
                    duration: const Duration(milliseconds: 1200),
                    curve: Curves.easeOutCubic,
                    builder: (context, val, child) {
                      return Text(
                        '${val.round()}%',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Custom Gradient Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    Container(
                      height: 20,
                      width: double.infinity,
                      color: AppColors.slate100,
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth * animatedProgress.clamp(0.0, 1.0);
                        return Container(
                          height: 20,
                          width: width,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.primaryLight,
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Occupancy Arc Meter ──────────────────────────────────────────────────────

class _OccupancyArcMeter extends StatefulWidget {
  _OccupancyArcMeter({
    required this.propertiesWithMatch,
    required this.propertiesCount,
    required this.expectedRevenue,
  });

  final int propertiesWithMatch;
  final int propertiesCount;
  final double expectedRevenue;

  @override
  State<_OccupancyArcMeter> createState() => _OccupancyArcMeterState();
}

class _OccupancyArcMeterState extends State<_OccupancyArcMeter> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final double occupancyRate = widget.propertiesCount == 0
        ? 0.0
        : (widget.propertiesWithMatch / widget.propertiesCount)
            .clamp(0.0, 1.0);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: occupancyRate),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeOutCubic,
      builder: (context, animatedRate, _) {
        final bool isHigh = animatedRate > 0.48;

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.landlordDashboardScreenEec75f83,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.landlordDashboardScreenBc2e631f(widget.propertiesCount),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: SizedBox(
                  height: 160,
                  width: 160,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // Circular wave container
                          Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primary,
                                width: 3.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.15),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: CustomPaint(
                                painter: _WavePainter(
                                  progress: animatedRate,
                                  waveValue: _controller.value,
                                  waveColor: AppColors.primary,
                                  backWaveColor: AppColors.primaryLight.withValues(alpha: 0.4),
                                ),
                              ),
                            ),
                          ),
                          // Text overlay
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(animatedRate * 100).round()}%',
                                style: TextStyle(
                                  color: isHigh ? Colors.white : AppColors.textPrimary,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                  shadows: isHigh ? [
                                    Shadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    )
                                  ] : null,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                l10n.landlordDashboardScreenB0164098,
                                style: TextStyle(
                                  color: isHigh
                                      ? Colors.white.withValues(alpha: 0.95)
                                      : AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  shadows: isHigh ? [
                                    Shadow(
                                      color: Colors.black.withValues(alpha: 0.1),
                                      blurRadius: 2,
                                      offset: const Offset(0, 1),
                                    )
                                  ] : null,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Bottom stats row
              Row(
                children: [
                  Expanded(
                    child: _ArcStatChip(
                      label: l10n.landlordDashboardScreenB0164098,
                      value: '${widget.propertiesWithMatch}',
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ArcStatChip(
                      label: l10n.landlordDashboardScreenFa311e7d,
                      value: '${(widget.propertiesCount - widget.propertiesWithMatch).clamp(0, widget.propertiesCount)}',
                      color: AppColors.border,
                      textColor: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ArcStatChip extends StatelessWidget {
  const _ArcStatChip({
    required this.label,
    required this.value,
    required this.color,
    this.textColor,
  });
  final String label;
  final String value;
  final Color color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final tc = textColor ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: tc, fontSize: 12, fontWeight: FontWeight.w600)),
          Text(value,
              style: TextStyle(
                  color: tc, fontSize: 18, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.progress,
    required this.waveValue,
    required this.waveColor,
    required this.backWaveColor,
  });

  final double progress;
  final double waveValue;
  final Color waveColor;
  final Color backWaveColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double width = size.width;
    final double height = size.height;

    // Background fill
    final bgPaint = Paint()..color = AppColors.slate50;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

    if (progress <= 0.0) return;

    final double baseHeight = height * (1.0 - progress);

    // Wave parameters
    const double waveAmplitude = 6.0;
    const double waveFrequency = 1.3;

    // 1. Back wave
    final Path backPath = Path();
    backPath.moveTo(0, baseHeight);
    for (double x = 0; x <= width; x++) {
      final double waveOffset = waveValue * 2 * math.pi;
      final double y = baseHeight +
          math.sin((x / width) * 2 * math.pi * waveFrequency + waveOffset) *
              waveAmplitude;
      backPath.lineTo(x, y);
    }
    backPath.lineTo(width, height);
    backPath.lineTo(0, height);
    backPath.close();

    final Paint backPaint = Paint()
      ..color = backWaveColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(backPath, backPaint);

    // 2. Front wave
    final Path frontPath = Path();
    frontPath.moveTo(0, baseHeight);
    for (double x = 0; x <= width; x++) {
      final double waveOffset = waveValue * 2 * math.pi + (math.pi * 0.7);
      final double y = baseHeight +
          math.sin((x / width) * 2 * math.pi * waveFrequency - waveOffset) *
              waveAmplitude;
      frontPath.lineTo(x, y);
    }
    frontPath.lineTo(width, height);
    frontPath.lineTo(0, height);
    frontPath.close();

    final Paint frontPaint = Paint()
      ..color = waveColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(frontPath, frontPaint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.waveValue != waveValue;
  }
}

// ─── Weekly Activity Chart ────────────────────────────────────────────────────

class _WeeklyActivityChart extends StatefulWidget {
  _WeeklyActivityChart({
    required this.properties,
    required this.isGuest,
  });

  final List<RentalProperty> properties;
  final bool isGuest;

  @override
  State<_WeeklyActivityChart> createState() => _WeeklyActivityChartState();
}

class _WeeklyActivityChartState extends State<_WeeklyActivityChart> {
  int _selectedBarIndex = -1; // -1 = auto (today / current period)
  int _selectedPeriod = 0; // 0=weekly, 1=monthly, 2=yearly

  List<String> _periods(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      l10n.landlordDashboardScreen50296d4c,
      l10n.landlordDashboardScreen3ec09dc0,
      l10n.landlordDashboardScreen8951e6dc,
    ];
  }

  List<String> _titleSuffix(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      l10n.landlordDashboardScreen43b23f14,
      l10n.landlordDashboardScreenAf52bcd6,
      l10n.landlordDashboardScreenBa6767e5,
    ];
  }

  List<List<String>> _labels(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      [
        l10n.landlordDashboardScreen270bf5ed,
        l10n.landlordDashboardScreen8f61d08b,
        l10n.landlordDashboardScreenAf1c561b,
        l10n.landlordDashboardScreenC7179c6f,
        l10n.landlordDashboardScreen5dee9138,
        l10n.landlordDashboardScreen93aec056,
        l10n.landlordDashboardScreenBda0900b,
      ],
      [
        l10n.landlordDashboardScreenA6b97c1e,
        l10n.landlordDashboardScreen9aff6d23,
        l10n.landlordDashboardScreenF960defe,
        l10n.landlordDashboardScreen04e8f590,
      ],
      [
        l10n.landlordDashboardScreen19035156,
        l10n.landlordDashboardScreen8cc85ded,
        l10n.landlordDashboardScreenC0394ea3,
        l10n.landlordDashboardScreenDc6b970f,
        l10n.landlordDashboardScreen5fa88202,
        l10n.landlordDashboardScreen477d76d2,
        l10n.landlordDashboardScreenA1f2e9ed,
        l10n.landlordDashboardScreen574d25b5,
        l10n.landlordDashboardScreen5a24ce53,
        l10n.landlordDashboardScreen4d43f4d5,
        l10n.landlordDashboardScreen6f0a4de2,
        l10n.landlordDashboardScreenD30ca257,
      ],
    ];
  }

  // Demo data for guest mode
  static const _demoData = [
    [3, 7, 5, 9, 4, 6, 2],
    [28, 35, 22, 41],
    [18, 24, 31, 27, 36, 42, 38, 29, 44, 37, 51, 46],
  ];

  // HONEST chart: the app stores no per-day/week/month interest history — only a
  // lifetime like total and today's likes. So we plot the REAL value we know
  // (today's likes) in the current bucket and leave the rest at 0, rather than
  // fabricating a distribution across days that never happened.
  List<int> _buildRealData(int period) {
    final now = DateTime.now();
    final properties = widget.properties;
    final todayLikes = properties.fold<int>(
        0, (s, p) => s + p.marketSignals.likesTodayFor(now));

    switch (period) {
      case 0: // Weekly: 7 days — today only.
        final bars = List<int>.filled(7, 0);
        bars[now.weekday % 7] = todayLikes;
        return bars;
      case 1: // Monthly: 4 weeks — this (most recent) week only.
        final bars = List<int>.filled(4, 0);
        bars[0] = todayLikes;
        return bars;
      case 2: // Yearly: 12 months — this month only.
        final bars = List<int>.filled(12, 0);
        bars[now.month - 1] = todayLikes;
        return bars;
      default:
        return [];
    }
  }

  List<int> _currentData() {
    if (widget.isGuest) return _demoData[_selectedPeriod];
    return _buildRealData(_selectedPeriod);
  }

  int _defaultBarIndex(List<int> data) {
    if (widget.isGuest) return 3;
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 0:
        return now.weekday % 7; // today
      case 1:
        return 0; // this week
      case 2:
        return now.month - 1; // this month
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentData = _currentData();
    final currentLabels = _labels(context)[_selectedPeriod];
    final maxVal = currentData.isEmpty ? 1 : currentData.reduce((a, b) => a > b ? a : b);
    final totalInquiries = currentData.fold<int>(0, (s, v) => s + v);
    final avgPerPeriod = currentData.isEmpty ? 0.0 : totalInquiries / currentData.length;
    final safeBarIndex = _selectedBarIndex < 0
        ? _defaultBarIndex(currentData)
        : _selectedBarIndex.clamp(0, currentData.length - 1);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.landlordDashboardScreenA21a4640(
                        _titleSuffix(context)[_selectedPeriod]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.slate100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      l10n.landlordDashboardScreen7203ea03,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              ),
              const SizedBox(width: 8),
              // Period selector
              Container(
                decoration: BoxDecoration(
                  color: AppColors.slate100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(_periods(context).length, (i) {
                    final selected = i == _selectedPeriod;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selectedPeriod = i;
                          _selectedBarIndex = -1; // reset to auto
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _periods(context)[i],
                          style: TextStyle(
                            color: selected ? Colors.white : AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Summary row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.landlordDashboardScreen4ff60e81,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.landlordDashboardScreenE8a3f079(totalInquiries),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedPeriod == 0
                        ? l10n.landlordDashboardScreen66b405bd
                        : _selectedPeriod == 1
                            ? l10n.landlordDashboardScreenAcc6e3d2
                            : l10n.landlordDashboardScreenE679dd5d,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    avgPerPeriod.toStringAsFixed(1),
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Bar Chart
          SizedBox(
            height: 160,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(currentData.length, (index) {
                final val = currentData[index];
                final heightFactor = maxVal > 0 ? val / maxVal : 0.0;
                final isHighlighted = index == safeBarIndex;

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedBarIndex = index);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isHighlighted) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Text(
                              '$val',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                        ] else
                          const SizedBox(height: 24),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: currentData.length > 8 ? 3 : 5,
                            ),
                            child: FractionallySizedBox(
                              heightFactor: heightFactor.clamp(0.04, 1.0),
                              alignment: Alignment.bottomCenter,
                              child: CustomPaint(
                                size: Size.infinite,
                                painter: _BarPainter(
                                  isHighlighted: isHighlighted,
                                  themeColor: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          currentLabels[index],
                          style: TextStyle(
                            color: isHighlighted
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            fontSize: currentData.length > 8 ? 9 : 11,
                            fontWeight: isHighlighted
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Striped Bar Painter ──────────────────────────────────────────────────────

class _BarPainter extends CustomPainter {
  const _BarPainter({
    required this.isHighlighted,
    required this.themeColor,
  });

  final bool isHighlighted;
  final Color themeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));

    canvas.save();
    canvas.clipRRect(rrect);

    final bgPaint = Paint();
    if (isHighlighted) {
      bgPaint.color = themeColor;
    } else {
      bgPaint.color = AppColors.slate100;
    }
    canvas.drawRect(rect, bgPaint);

    final stripePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    if (isHighlighted) {
      stripePaint.color = Colors.white.withValues(alpha: 0.22);
    } else {
      stripePaint.color = themeColor.withValues(alpha: 0.12);
    }

    const double step = 11.0;
    for (double i = -size.height; i < size.width + size.height; i += step) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        stripePaint,
      );
    }

    canvas.restore();

    if (size.height > 25) {
      final dotCenter = Offset(size.width / 2, 14);
      final outerCirclePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(dotCenter, 6.5, outerCirclePaint);

      final innerDotPaint = Paint()
        ..color = isHighlighted ? themeColor : AppColors.slate900
        ..style = PaintingStyle.fill;
      canvas.drawCircle(dotCenter, 3.5, innerDotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter oldDelegate) {
    return oldDelegate.isHighlighted != isHighlighted ||
        oldDelegate.themeColor != themeColor;
  }
}

// ─── Landlord Tools Section ───────────────────────────────────────────────────
// Big, plain-Hebrew helpers aimed at older, non-technical landlords. Each row
// is a large tappable card with an icon, a clear title and a one-line
// explanation, opening the dedicated tool screen.

// ─── Broker Hub Card (מתווך only) ─────────────────────────────────────────────
// Highlighted indigo card shown above the landlord tools when the user is a
// broker. Opens the "כלי הסוכן" hub with all 10 broker tools.
class _BrokerToolsCard extends StatelessWidget {
  _BrokerToolsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // AppColors.primary/primaryDark are mutable (indigo for brokers) — read
    // here at build time; this widget must stay outside any const context.
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BrokerToolsScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.30),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                IconsaxPlusLinear.briefcase,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.landlordDashboardScreen2074036b,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.landlordDashboardScreen0a134a61,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              IconsaxPlusLinear.arrow_left_2,
              color: Colors.white,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _LandlordToolsSection extends StatelessWidget {
  _LandlordToolsSection({required this.properties});

  final List<RentalProperty> properties;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final firstProperty = properties.isNotEmpty ? properties.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 40,
              margin: const EdgeInsets.only(top: 2, left: 12),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.landlordDashboardScreen299b769f,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.landlordDashboardScreenC7fa5680,
                    style: const TextStyle(
                      color: AppColors.slate500,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Area Intelligence — where to invest + who a location suits. Shown to
        // every landlord (brokers also reach it from "כלי הסוכן").
        _ToolTile(
          icon: IconsaxPlusLinear.map_1,
          color: AppColors.success,
          title: l10n.landlordDashboardScreenA8bb0310,
          subtitle: l10n.landlordDashboardScreen4e175795,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AreaIntelScreen()),
          ),
        ),
        const SizedBox(height: 12),
        // Income-tax helper — landlords only; removed from the broker (סוכן) account.
        if (!context.watch<DatingProvider>().isBroker) ...[
          _ToolTile(
            icon: IconsaxPlusLinear.receipt_text,
            color: AppColors.primary,
            title: l10n.landlordDashboardScreenAaafbb6b,
            subtitle: l10n.landlordDashboardScreenDfd3460d,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TaxHelperScreen(
                  initialMonthlyRent: firstProperty?.price.toDouble(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _ToolTile(
          icon: IconsaxPlusLinear.notification_bing,
          color: AppColors.coral,
          title: l10n.landlordDashboardScreenCa25d18a,
          subtitle: l10n.landlordDashboardScreen8b96a6ac,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RemindersScreen()),
          ),
        ),
        const SizedBox(height: 12),
        _ToolTile(
          icon: IconsaxPlusLinear.wallet_money,
          color: AppColors.primaryDark,
          title: l10n.landlordDashboardScreen5308aa0d,
          subtitle: firstProperty == null
              ? l10n.landlordDashboardScreen9fd83dca
              : l10n.landlordDashboardScreen7e05b276,
          onTap: firstProperty == null
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PaymentTrackingHubScreen(
                        properties: [
                          for (final p in properties)
                            (id: p.id, title: p.address, rent: p.price),
                        ],
                      ),
                    ),
                  ),
        ),
      ],
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onTap!();
                }
              : null,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.slate200),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                // Gradient-tinted icon tile
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: 0.16),
                        color.withValues(alpha: 0.06),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: color.withValues(alpha: 0.12)),
                  ),
                  child: Icon(icon, color: color, size: 25),
                ),
                const SizedBox(width: 14),
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
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.slate500,
                          fontSize: 12.5,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Chevron in a soft circle (RTL: points left = forward)
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: AppColors.slate50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    IconsaxPlusLinear.arrow_left_2,
                    color: AppColors.slate400,
                    size: 17,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── My Calendar Card ─────────────────────────────────────────────────────────
// Prominent standalone card near the top of the dashboard. Lets the landlord
// open the availability calendar to mark free viewing windows tenants can book.
class _CalendarCard extends StatefulWidget {
  _CalendarCard({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_CalendarCard> createState() => _CalendarCardState();
}

class _CalendarCardState extends State<_CalendarCard>
    with WidgetsBindingObserver {
  final AvailabilityRepository _repo = AvailabilityRepository();

  AvailabilitySlot? _nextBooked;
  bool _loading = true;

  /// The initial didChangeDependencies fires only to register the provider
  /// dependency; later fires mean the provider notified (e.g. a new viewing was
  /// booked) → reload.
  bool _dependenciesReady = false;

  List<String> _daysOfWeek(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      l10n.landlordDashboardScreenDae6b270,
      l10n.landlordDashboardScreen47f34119,
      l10n.landlordDashboardScreenDb0c22fc,
      l10n.landlordDashboardScreenDa1dae77,
      l10n.landlordDashboardScreenCe94cfff,
      l10n.landlordDashboardScreen7e718908,
      l10n.landlordDashboardScreen4203bd7e,
    ];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh "next viewing" whenever the watched DatingProvider notifies —
    // e.g. right after processViewingConfirms() books a slot — so the card is
    // never stale (SCHED-3). The first call just registers the dependency.
    if (_dependenciesReady) {
      _load();
    } else {
      _dependenciesReady = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning to the app can surface viewings booked while the landlord was
    // elsewhere; reload so the next-viewing line stays current (SCHED-3).
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final all = await _repo.loadAll();
    final now = DateTime.now();
    final booked = all
        .where((s) => s.status == SlotStatus.booked && s.start.isAfter(now))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    if (!mounted) return;
    setState(() {
      _nextBooked = booked.isEmpty ? null : booked.first;
      _loading = false;
    });
  }

  String _whenLabel(BuildContext context, DateTime d) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = target.difference(today).inDays;
    final weekday = _daysOfWeek(context)[d.weekday % 7];
    final day = diff == 0
        ? l10n.landlordDashboardScreen95d86d7f
        : diff == 1
            ? l10n.landlordDashboardScreen840835ac
            // Within a week the weekday name is unambiguous; beyond that add the
            // date so "Tuesday" 9 days out isn't confused with this Tuesday.
            : diff < 7
                ? l10n.landlordDashboardScreen30744d51(weekday)
                : l10n.landlordDashboardScreen2dd36976(weekday, d.day, d.month);
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$day · $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Subscribe to the provider so didChangeDependencies re-fires (and we
    // reload) whenever a viewing is booked via processViewingConfirms (SCHED-3).
    context.watch<DatingProvider>();

    final booked = _nextBooked;
    final hasBooking = booked != null;

    final String title;
    final String subtitle;
    if (_loading) {
      title = l10n.landlordDashboardScreenD1b5aeb8;
      subtitle = l10n.landlordDashboardScreen32fb9ba0;
    } else if (hasBooking) {
      final who = booked.bookedByName.trim().isEmpty
          ? l10n.landlordDashboardScreenF12b53ff
          : booked.bookedByName.trim();
      title = l10n.landlordDashboardScreen6db621c3(who);
      subtitle = _whenLabel(context, booked.start);
    } else {
      title = l10n.landlordDashboardScreenD1b5aeb8;
      subtitle = l10n.landlordDashboardScreen7dec25c8;
    }

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.slate200),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.10),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              // Calendar icon on a brand-tinted tile
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary,
                      AppColors.primaryDark,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(
                  hasBooking
                      ? IconsaxPlusLinear.calendar_tick
                      : IconsaxPlusLinear.calendar_1,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasBooking
                            ? AppColors.primary
                            : AppColors.slate500,
                        fontSize: 13,
                        fontWeight:
                            hasBooking ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Chevron in a soft circle (RTL: points left = forward)
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  IconsaxPlusLinear.arrow_left_2,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}