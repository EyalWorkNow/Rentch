import 'dart:math' as math;
import 'dart:ui';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/presentation/features/calendar/availability_calendar_screen.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/add_property_screen.dart'
    show AddPropertyScreen, EditPropertyScreen;
import 'package:dating_app/presentation/screens/assistant_screen.dart';
import 'package:dating_app/presentation/screens/message_screen.dart';
import 'package:dating_app/presentation/screens/notifications_screen.dart';
import 'package:dating_app/presentation/screens/rent_tracking_screen.dart';
import 'package:dating_app/presentation/features/tax/tax_helper_screen.dart';
import 'package:dating_app/presentation/features/landlord/reminders_screen.dart';
import 'package:dating_app/presentation/features/broker/area_intel_screen.dart';
import 'package:dating_app/presentation/features/broker/broker_tools_screen.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:dating_app/presentation/widgets/property_share_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:dating_app/presentation/widgets/pulse_widget.dart';
import 'package:dating_app/presentation/widgets/fade_slide_entrance.dart';
import 'package:provider/provider.dart';
import 'package:dating_app/presentation/widgets/animations/micro_animations.dart';

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
        
        // Calculate Expected Monthly Revenue
        final double expectedRevenue = properties.fold<double>(
          0.0,
          (sum, property) => sum + property.price,
        );

        if (provider.isLoading) {
          return Scaffold(
            backgroundColor: Color(0xFFF5F7FA),
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
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
                    propertiesCount: properties.length,
                    expectedRevenue: expectedRevenue,
                    conversionRate: stats.conversionRate,
                    pendingCount: stats.pendingCount,
                  ),
                ),
                const SizedBox(height: 20),

                // ── Occupancy Arc Meter ──
                FadeSlideEntrance(
                  delay: const Duration(milliseconds: 160),
                  child: _OccupancyArcMeter(
                    matchesCount: stats.matchesCount,
                    propertiesCount: properties.length,
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

                // ── Quick Actions Grid ──
                FadeSlideEntrance(
                  delay: const Duration(milliseconds: 320),
                  child: _QuickActionsGrid(
                    pendingCount: stats.pendingCount,
                    unseenCount: provider.unseenMatchCount,
                    onAddProperty: () =>
                        _push(context, const AddPropertyScreen()),
                    onSwipes: onOpenSwipes,
                    onMatches: onOpenMatches,
                    onProperties: onOpenProperties,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Broker hub (מתווך only) — opens "כלי הסוכן" ──
                if (context.watch<DatingProvider>().isBroker) ...[
                  FadeSlideEntrance(
                    delay: const Duration(milliseconds: 340),
                    child: const _BrokerToolsCard(),
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
                const SizedBox(height: 24),

                // ── Active Matches ──
                if (matches.isNotEmpty) ...[
                  FadeSlideEntrance(
                    delay: const Duration(milliseconds: 400),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Properties Scroll ──
                if (properties.isNotEmpty) ...[
                  FadeSlideEntrance(
                    delay: const Duration(milliseconds: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                      ],
                    ),
                  ),
                ] else ...[
                  FadeSlideEntrance(
                    delay: const Duration(milliseconds: 480),
                    child: _EmptyPropertiesCard(
                      onAdd: () => _push(context, const AddPropertyScreen()),
                    ),
                  ),
                ],
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
  const _DashboardHeader({
    required this.name,
    required this.photoUrl,
    required this.pendingCount,
  });

  final String name;
  final String photoUrl;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
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
                      text: 'שלום, ',
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
                    ? '$pendingCount מועמדים ממתינים לאישורך'
                    : 'הכל מעודכן ותחת שליטה ✓',
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
            const NotificationBell(),
            const SizedBox(width: 10),
            // Personal assistant ("עוזר אישי") — replaces the avatar. A clear
            // icon + tag opens Erik, the voice/text assistant built for older
            // landlords.
            const _AssistantChip(),
          ],
        ),
      ],
    );
  }
}

class _AssistantChip extends StatelessWidget {
  const _AssistantChip();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AssistantScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 13, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, Color(0xFF0E9AA3)],
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
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(IconsaxPlusBold.microphone_2, color: Colors.white, size: 20),
            SizedBox(width: 7),
            Text(
              'עוזר אישי',
              style: TextStyle(
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'סיכום',
          style: TextStyle(
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
                title: 'סה״כ נכסים',
                value: propertiesCount.toDouble(),
                unit: 'פעילים',
                backgroundColor: Colors.white,
                isPrice: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: 'הכנסה צפויה',
                value: expectedRevenue,
                unit: 'חודשי',
                backgroundColor: Colors.white,
                isPrice: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _LargeProgressCard(
          title: 'כמה מהמתעניינים הסכמתם להם',
          progressValue: conversionRate / 100.0,
          conversionRate: conversionRate,
          statusText: pendingCount > 0
              ? '$pendingCount ממתינים לאישור שלך'
              : 'אין מועמדים שממתינים',
          icon: IconsaxPlusLinear.flash,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
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
  const _LargeProgressCard({
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
                      color: const Color(0xFFEDF1F5),
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
  const _OccupancyArcMeter({
    required this.matchesCount,
    required this.propertiesCount,
    required this.expectedRevenue,
  });

  final int matchesCount;
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
    final double occupancyRate = widget.propertiesCount == 0
        ? 0.0
        : (widget.matchesCount / widget.propertiesCount).clamp(0.0, 1.0);

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
              const Text(
                'נכסים עם התאמה',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'מתוך ${widget.propertiesCount} נכסים פעילים',
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
                                'עם התאמה',
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
                      label: 'עם התאמה',
                      value: '${widget.matchesCount}',
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ArcStatChip(
                      label: 'ממתינים',
                      value: '${(widget.propertiesCount - widget.matchesCount).clamp(0, widget.propertiesCount)}',
                      color: const Color(0xFFE8EDF2),
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
    final bgPaint = Paint()..color = const Color(0xFFF6FAFC);
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
  const _WeeklyActivityChart({
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
  int _selectedPeriod = 0; // 0=שבועי, 1=חודשי, 2=שנתי

  static const _periods = ['שבועי', 'חודשי', 'שנתי'];
  static const _titleSuffix = ['השבוע', 'החודש', 'השנה'];

  static const _labels = [
    ['א\'', 'ב\'', 'ג\'', 'ד\'', 'ה\'', 'ו\'', 'ש\''],
    ['שב׳ 1', 'שב׳ 2', 'שב׳ 3', 'ש׳ 4'],
    ['ינו', 'פבר', 'מרץ', 'אפר', 'מאי', 'יונ', 'יול', 'אוג', 'ספט', 'אוק', 'נוב', 'דצמ'],
  ];

  // Demo data for guest mode
  static const _demoData = [
    [3, 7, 5, 9, 4, 6, 2],
    [28, 35, 22, 41],
    [18, 24, 31, 27, 36, 42, 38, 29, 44, 37, 51, 46],
  ];

  /// Distribute [total] across [count] bars such that bar at [peakIndex]
  /// is the largest. Uses a deterministic seed so values are stable across rebuilds.
  List<int> _distribute(int total, int count, int peakIndex, int seed) {
    if (total == 0) return List.filled(count, 0);
    // Build weights biased toward peakIndex using seed for stability
    final weights = List<double>.generate(count, (i) {
      final dist = (i - peakIndex).abs();
      // Deterministic variation based on seed
      final variation = ((seed * (i + 1) * 7) % 5) / 10.0; // 0.0 to 0.4
      return (1.0 / (dist + 1)) + variation;
    });
    final sumW = weights.fold<double>(0.0, (s, w) => s + w);
    final result = List<int>.filled(count, 0);
    int assigned = 0;
    for (var i = 0; i < count; i++) {
      result[i] = ((weights[i] / sumW) * total).round();
      assigned += result[i];
    }
    // Fix rounding drift on peak bar
    result[peakIndex] += total - assigned;
    if (result[peakIndex] < 0) result[peakIndex] = 0;
    return result;
  }

  List<int> _buildRealData(int period) {
    final now = DateTime.now();
    final properties = widget.properties;

    // Total lifetime likes across all landlord properties
    final totalLikes = properties.fold<int>(0, (s, p) => s + p.marketSignals.likes);
    // Today's likes (using the model's built-in helper)
    final todayLikes = properties.fold<int>(
      0, (s, p) => s + p.marketSignals.likesTodayFor(now));

    // Seed derived from property IDs for stable random look
    final seed = properties.isEmpty
        ? 42
        : properties.map((p) => p.id.hashCode).fold<int>(0, (a, b) => a ^ b).abs();

    switch (period) {
      case 0: // Weekly: 7 days, today = weekday index (Sun=0)
        final todayIndex = now.weekday % 7; // DateTime.monday=1..sunday=7 -> 0=Sun
        final remaining = (totalLikes - todayLikes).clamp(0, totalLikes);
        final base = _distribute(remaining, 7, todayIndex, seed);
        base[todayIndex] = (base[todayIndex] + todayLikes).clamp(0, 9999);
        return base;

      case 1: // Monthly: 4 weeks, this week = index 0 (most recent)
        final base = _distribute(totalLikes, 4, 0, seed);
        // Ensure this week is at least todayLikes
        if (base[0] < todayLikes) base[0] = todayLikes;
        return base;

      case 2: // Yearly: 12 months, current month = index based on month
        final monthIndex = now.month - 1; // 0-based
        return _distribute(totalLikes, 12, monthIndex, seed);

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
    final currentData = _currentData();
    final currentLabels = _labels[_selectedPeriod];
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
                    'מתעניינים בנכסים שלך ${_titleSuffix[_selectedPeriod]}',
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
                      color: const Color(0xFFF1F4F8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'הערכה לפי הפעילות',
                      style: TextStyle(
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
                  color: const Color(0xFFF1F4F8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(_periods.length, (i) {
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
                          _periods[i],
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
                  const Text(
                    'סה״כ פניות',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$totalInquiries פניות',
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
                        ? 'ממוצע יומי'
                        : _selectedPeriod == 1
                            ? 'ממוצע שבועי'
                            : 'ממוצע חודשי',
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
      bgPaint.color = const Color(0xFFF1F3F9);
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
        ..color = isHighlighted ? themeColor : const Color(0xFF0F172A)
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
          key: Key('quick_actions_header'),
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QABtn(
                label: 'הוסף דירה',
                icon: IconsaxPlusLinear.add_square,
                color: AppColors.primary,
                onTap: onAddProperty,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QABtn(
                label: 'מועמדים',
                icon: IconsaxPlusLinear.profile_2user,
                badge: pendingCount,
                color: AppColors.textPrimary,
                onTap: onSwipes,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QABtn(
                label: "מאצ'ים",
                icon: IconsaxPlusLinear.heart,
                badge: unseenCount,
                color: AppColors.coral,
                onTap: onMatches,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QABtn(
                label: 'הנכסים',
                icon: IconsaxPlusLinear.buildings_2,
                color: AppColors.primaryDark,
                onTap: onProperties,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // היומן — mark free viewing windows tenants can book from the chat.
        Row(
          children: [
            Expanded(
              child: _QABtn(
                label: 'היומן שלי — זמנים פנויים לצפייה',
                icon: IconsaxPlusLinear.calendar_1,
                color: AppColors.primary,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AvailabilityCalendarScreen(),
                  ),
                ),
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
    required this.color,
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
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
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
                            ? AppColors.primary
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
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
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
  const _BrokerToolsCard();

  @override
  Widget build(BuildContext context) {
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
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'כלי הסוכן',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'פנקס לקוחות, התאמות, פייפליין, צפיות ועוד',
                    style: TextStyle(
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
  const _LandlordToolsSection({required this.properties});

  final List<RentalProperty> properties;

  @override
  Widget build(BuildContext context) {
    final firstProperty = properties.isNotEmpty ? properties.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'כלים לבעל הדירה',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'עזרה פשוטה לניהול הדירה — בלי כאב ראש',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 14),
        // Area Intelligence — where to invest + who a location suits. Shown to
        // every landlord (brokers also reach it from "כלי הסוכן").
        _ToolTile(
          icon: IconsaxPlusLinear.map_1,
          color: AppColors.success,
          title: 'אינטליגנציית אזור',
          subtitle: 'כתובת → כל נתוני האזור ולמי הוא הכי מתאים להשקעה',
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
            title: 'מס הכנסה — בקלות',
            subtitle: 'בדיקה מהירה אם צריך לשלם מס על השכירות',
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
          title: 'תזכורות',
          subtitle: 'שלא תשכח חידוש חוזה, תשלום או ביטוח',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RemindersScreen()),
          ),
        ),
        const SizedBox(height: 12),
        _ToolTile(
          icon: IconsaxPlusLinear.wallet_money,
          color: AppColors.primaryDark,
          title: 'מעקב תשלומים',
          subtitle: firstProperty == null
              ? 'הוסיפו דירה כדי לעקוב אחרי תשלומי השכירות'
              : 'לראות מי שילם שכר דירה ומי עדיין חייב',
          onTap: firstProperty == null
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RentTrackingScreen(
                        propertyId: firstProperty.id,
                        propertyTitle: firstProperty.address,
                        monthlyRent: firstProperty.price,
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
    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onTap!();
            }
          : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.55,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                IconsaxPlusLinear.arrow_left_2,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
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
    return AvatarPulseRing(
      active: true,
      child: Container(
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
              _InitialsCircle(initials: initials),
              if (photoUrl.isNotEmpty)
                Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
            ],
          ),
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
        icon: IconsaxPlusLinear.profile_2user,
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
        icon: IconsaxPlusLinear.message,
        color: AppColors.coral,
        title: '$unseen הודעות שלא נקראו',
        subtitle: 'שוכרים שכבר אישרת ממתינים לתגובה שלך',
        cta: 'לשיחות',
        onTap: onOpenMatches,
      ));
    }

    if (props.isEmpty) {
      items.add(_ActivityItem(
        icon: IconsaxPlusLinear.add_square,
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
        icon: IconsaxPlusLinear.chart_2,
        color: Colors.white.withValues(alpha: 0.9),
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
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
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
    final iconBgColor = item.color.withValues(alpha: 0.08);

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
                    color: iconBgColor,
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
                          color: AppColors.textPrimary,
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
                  const RentlyIcon(IconsaxPlusLinear.arrow_left,
                      size: 14,
                      color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
        if (!isLast)
          const Divider(
            height: 1,
            indent: 70,
            color: Color(0xFFEDF1F5),
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
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'הכל',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(width: 3),
                  RentlyIcon(IconsaxPlusLinear.arrow_left,
                      size: 12, color: AppColors.primary),
                ],
              ),
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
    final isUnread = match.messages.isNotEmpty && !match.ownerSigned;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MessageScreen(matchId: match.id)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // Left accent bar
            Container(
              width: 4,
              height: 76,
              decoration: BoxDecoration(
                color: status.color,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Property thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 60,
                height: 60,
                child: property.media.isNotEmpty
                    ? SafeMedia(
                        media: property.media.first,
                        fallback: Container(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          child: Center(
                            child: RentlyIcon(IconsaxPlusLinear.building,
                                color: AppColors.primary, size: 22),
                          ),
                        ),
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      )
                    : Container(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        child: Center(
                          child: RentlyIcon(IconsaxPlusLinear.building,
                              color: AppColors.primary, size: 22),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
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
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusBadge(label: status.label, color: status.color),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (isUnread)
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(left: 5),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            lastMsg ?? 'שיחה חדשה ממתינה',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isUnread
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: isUnread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Arrow CTA
            Container(
              width: 34,
              height: 34,
              margin: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: RentlyIcon(
                  IconsaxPlusLinear.arrow_left,
                  color: Colors.white,
                  size: 16,
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
      return (label: 'פעיל', color: AppColors.textPrimary);
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 10.5, fontWeight: FontWeight.w800),
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
          border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image
              Positioned.fill(
                child: media != null
                    ? SafeMedia(
                        media: media,
                        fallback: Container(
                          color: const Color(0xFF06243A),
                          child: const Center(
                            child: RentlyIcon(IconsaxPlusLinear.building,
                                color: Colors.white30, size: 32),
                          ),
                        ),
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      )
                    : Container(
                        color: const Color(0xFF06243A),
                        child: const Center(
                          child: RentlyIcon(IconsaxPlusLinear.building,
                              color: Colors.white30, size: 32),
                        ),
                      ),
              ),
              // Bottom dark gradient overlay for text readability
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 105,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.85),
                          Colors.black.withValues(alpha: 0.4),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Details
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      property.city.isNotEmpty
                          ? property.city
                          : property.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${property.priceLabel} • ${property.roomsLabel} ח\'',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Builder(
                      builder: (context) {
                        final isSale = property.transactionType == PropertyTransactionType.sale;
                        final isActive = property.isActive;
                        final String statusText;
                        final Color statusColor;

                        if (isActive) {
                          statusText = isSale ? 'למכירה' : 'להשכרה';
                          statusColor = AppColors.primary;
                        } else {
                          statusText = isSale ? 'נמכר' : 'הושכר';
                          statusColor = AppColors.textSecondary;
                        }

                        // Solid accent fill + white text — stays readable even
                        // when the broker theme makes statusColor black (the old
                        // translucent-black-on-black badge was unreadable).
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            statusText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        );
                      }
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
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
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: RentlyIcon(IconsaxPlusLinear.add_square,
                  color: AppColors.primary, size: 26),
            ),
            const SizedBox(height: 12),
            const Text(
              'הוסף את הנכס הראשון שלך',
              style: TextStyle(
                color: AppColors.textPrimary,
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
        color: Color(0xFF06243A),
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
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            property.address,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          _SheetTile(
            icon: IconsaxPlusLinear.edit,
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
            icon: IconsaxPlusLinear.trash,
            label: 'הסר נכס מהרשימה',
            color: AppColors.coral,
            onTap: () async {
              Navigator.pop(context);
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF06243A),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22)),
                  title: const Text('הסרת נכס',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w900)),
                  content: const Text('האם אתה בטוח שברצונך להסיר נכס זה?',
                      style: TextStyle(color: Colors.white70)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('ביטול',
                          style: TextStyle(color: Colors.white70)),
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
            icon: IconsaxPlusLinear.share,
            label: 'שתף קישור לנכס',
            color: Colors.white.withValues(alpha: 0.9),
            onTap: () {
              Navigator.pop(context);
              showPropertyShareSheet(context, property);
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
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color:
                    color == AppColors.coral ? AppColors.coral : Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
              ),
            ),
            const Spacer(),
            RentlyIcon(IconsaxPlusLinear.arrow_left,
                size: 16, color: Colors.white.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}
