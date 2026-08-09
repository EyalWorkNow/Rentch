part of '../property_detail_screen.dart';

/// Market Board (a.k.a. `dashboardGlass`) — a DATA / DASHBOARD identity for
/// investors. The hero bleeds edge-to-edge to the very top with readable overlay
/// controls and a price/address scrim. Below it sits a "terminal" market panel:
/// a live-pulse header, a grid of real market-signal metrics (views / saves /
/// likes / contact requests), a secondary read-out (₪ per m², days on market,
/// average dwell time, gallery swipes), and a real price-history sparkline.
/// The affordability read-out and the full shared parity block follow.
///
/// Self-contained, designer-owned unit. The exclusive helpers
/// ([_MarketMetricCard], [_MarketReadoutTile], [_MarketSparkline],
/// [_MarketBoardHeader], the [_SparklinePainter]) and the [_compactNumber] /
/// [_compactDuration] formatters live here. Shared building blocks (hero media,
/// parity sections, affordability strip) stay in the library head.
class _MarketBoardTemplate extends StatelessWidget {
  const _MarketBoardTemplate({
    required this.property,
    required this.branding,
    required this.controller,
    required this.currentPage,
    required this.onPageChanged,
    required this.reviews,
    required this.hasVirtualTour,
    required this.isLandlordPreview,
    required this.onBackTap,
    required this.onShareTap,
    required this.onLike,
    required this.onTour,
  });

  final RentalProperty property;
  final BrokerBrandingConfig branding;
  final PageController controller;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final List<AppReview> reviews;
  final bool hasVirtualTour;
  final bool isLandlordPreview;
  final VoidCallback onBackTap;
  final VoidCallback onShareTap;
  final VoidCallback onLike;
  final VoidCallback onTour;

  // ── Terminal palette ──────────────────────────────────────────────────────
  static const Color _panel = AppColors.ink;
  static const Color _panelEdge = AppColors.inkSoft;
  static const Color _grid = AppColors.ink;
  static const Color _ink = AppColors.slate100;
  static const Color _muted = AppColors.slate400;
  static const Color _up = Color(0xFF34D399);
  static const Color _down = AppColors.coral;

  /// Whole-day age of the listing — a real "days on market" read-out.
  int? get _daysOnMarket {
    final created = property.createdAt;
    if (created == null) return null;
    final age = DateTime.now().difference(created).inDays;
    return age < 0 ? null : age;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final signals = property.marketSignals;
    // Watch so live view / like counts refresh the board as they arrive.
    context.watch<DatingProvider>();
    final monthlyIncome =
        context.read<DatingProvider>().tenantProfile?.monthlyIncome;
    final topInset = MediaQuery.of(context).padding.top;

    final totalViews = signals.views + signals.detailViews;
    final accent = branding.primaryColor;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Edge-to-edge hero, bleeding to the very top ───────────────────────
        SliverToBoxAdapter(
          child: _MarketHero(
            property: property,
            branding: branding,
            controller: controller,
            currentPage: currentPage,
            onPageChanged: onPageChanged,
            topInset: topInset,
            onBackTap: onBackTap,
            onShareTap: onShareTap,
            onLike: onLike,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 124),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Market terminal panel ─────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _panel,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: _panelEdge),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MarketBoardHeader(
                        accent: accent,
                        liveViewers: signals.liveViewers,
                        lastViewedAt: signals.lastViewedAt,
                      ),
                      const SizedBox(height: 18),
                      // Primary signal grid (2×2). Real counts only; "—" if 0.
                      Row(
                        children: [
                          Expanded(
                            child: _MarketMetricCard(
                              icon: IconsaxPlusLinear.eye,
                              label: l10n.marketBoardTemplate48227f9c,
                              value: _compactNumber(totalViews),
                              accent: accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MarketMetricCard(
                              icon: IconsaxPlusLinear.archive_book,
                              label: l10n.marketBoardTemplate066de4f8,
                              value: _compactNumber(signals.saves),
                              accent: accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _MarketMetricCard(
                              icon: IconsaxPlusLinear.heart,
                              label: l10n.marketBoardTemplate07433e11,
                              value: _compactNumber(signals.likes),
                              accent: accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MarketMetricCard(
                              icon: IconsaxPlusLinear.message_2,
                              label: l10n.marketBoardTemplate23785eb4,
                              value: _compactNumber(signals.contactRequests),
                              accent: accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1, color: _grid),
                      const SizedBox(height: 16),
                      // Secondary read-out — real derived signals.
                      _MarketReadoutTile(
                        icon: IconsaxPlusLinear.ruler,
                        label: l10n.marketBoardTemplate60c1e500,
                        value: property.pricePerSquareMeter != null
                            ? '₪${_compactNumber(property.pricePerSquareMeter!)}'
                            : '—',
                        accent: accent,
                      ),
                      const _MarketReadoutDivider(),
                      _MarketReadoutTile(
                        icon: IconsaxPlusLinear.calendar_1,
                        label: l10n.marketBoardTemplate13f110df,
                        value: _daysOnMarket != null
                            ? (_daysOnMarket == 0
                                ? l10n.marketBoardTemplate95d86d7f
                                : '$_daysOnMarket')
                            : '—',
                        accent: accent,
                      ),
                      const _MarketReadoutDivider(),
                      _MarketReadoutTile(
                        icon: IconsaxPlusLinear.timer_1,
                        label: l10n.marketBoardTemplateD51f71fc,
                        value: signals.avgDetailStaySeconds > 0
                            ? _compactDuration(signals.avgDetailStaySeconds, l10n)
                            : '—',
                        accent: accent,
                      ),
                      const _MarketReadoutDivider(),
                      _MarketReadoutTile(
                        icon: IconsaxPlusLinear.gallery,
                        label: l10n.marketBoardTemplate261cf748,
                        value: signals.gallerySwipes > 0
                            ? _compactNumber(signals.gallerySwipes)
                            : '—',
                        accent: accent,
                      ),
                      // Real price history → sparkline (only with ≥2 points).
                      if (property.priceHistory.length >= 2) ...[
                        const SizedBox(height: 18),
                        _MarketSparkline(
                          history: property.priceHistory,
                          accent: accent,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // ── Affordability read-out (not part of parity → no dup) ──────
                _AffordabilityStrip(
                  property: property,
                  monthlyIncome: monthlyIncome,
                ),
                const SizedBox(height: 26),
                // ── Full shared parity block (gallery, facts, owner, tours,
                //    map, match insight, CTA — single source, no duplicates) ──
                _ParitySections(
                  property: property,
                  branding: branding,
                  controller: controller,
                  reviews: reviews,
                  hasVirtualTour: hasVirtualTour,
                  isLandlordPreview: isLandlordPreview,
                  onShareTap: onShareTap,
                  onTour: onTour,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Edge-to-edge hero with overlay controls + price/address scrim ────────────

class _MarketHero extends StatelessWidget {
  const _MarketHero({
    required this.property,
    required this.branding,
    required this.controller,
    required this.currentPage,
    required this.onPageChanged,
    required this.topInset,
    required this.onBackTap,
    required this.onShareTap,
    required this.onLike,
  });

  final RentalProperty property;
  final BrokerBrandingConfig branding;
  final PageController controller;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final double topInset;
  final VoidCallback onBackTap;
  final VoidCallback onShareTap;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.46;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _TemplateHeroMedia(
            property: property,
            controller: controller,
            currentPage: currentPage,
            onPageChanged: onPageChanged,
            height: height,
            radius: 0,
            overlay: _buildScrim(),
          ),
          // Top controls — translucent, readable over any image.
          Positioned(
            top: topInset + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                _RoundTemplateButton(
                  icon: IconsaxPlusLinear.arrow_right,
                  onTap: onBackTap,
                  color: Colors.white,
                  translucent: true,
                ),
                const Spacer(),
                _RoundTemplateButton(
                  icon: IconsaxPlusLinear.export_2,
                  onTap: onShareTap,
                  color: Colors.white,
                  translucent: true,
                ),
                const SizedBox(width: 10),
                _RoundTemplateButton(
                  icon: IconsaxPlusLinear.heart,
                  onTap: onLike,
                  color: Colors.white,
                  translucent: true,
                ),
              ],
            ),
          ),
          // Price + address read-out anchored at the base of the hero.
          Positioned(
            left: 18,
            right: 18,
            bottom: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      property.priceLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        property.priceSuffixLabel,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  property.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrim() {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.42, 1.0],
            colors: [
              Colors.black.withValues(alpha: 0.30),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.66),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Market board header (live ticker) ────────────────────────────────────────

class _MarketBoardHeader extends StatelessWidget {
  const _MarketBoardHeader({
    required this.accent,
    required this.liveViewers,
    required this.lastViewedAt,
  });

  final Color accent;
  final int liveViewers;
  final DateTime? lastViewedAt;

  String? _lastSeenLabel(AppLocalizations l10n) {
    final at = lastViewedAt;
    if (at == null) return null;
    final diff = DateTime.now().difference(at);
    if (diff.isNegative) return null;
    if (diff.inMinutes < 1) return l10n.marketBoardTemplate2c925bfb;
    if (diff.inMinutes < 60) {
      return l10n.marketBoardTemplateC88d38fc(diff.inMinutes);
    }
    if (diff.inHours < 24) {
      return l10n.marketBoardTemplate5787aec5(diff.inHours);
    }
    return l10n.marketBoardTemplate0a58ff05(diff.inDays);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final live = liveViewers > 0;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(IconsaxPlusLinear.chart_21, color: accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.marketBoardTemplate3af8a1a1,
                style: const TextStyle(
                  color: _MarketBoardTemplate._ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _lastSeenLabel(l10n) ?? l10n.marketBoardTemplate818d00f3,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _MarketBoardTemplate._muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (live)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: _MarketBoardTemplate._up.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _MarketBoardTemplate._up.withValues(alpha: 0.32),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SignalStripPulse(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: _MarketBoardTemplate._up,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  liveViewers == 1
                      ? l10n.marketBoardTemplate636e854d
                      : l10n.marketBoardTemplate9b8e10c5(liveViewers),
                  style: const TextStyle(
                    color: _MarketBoardTemplate._up,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Primary metric tile ──────────────────────────────────────────────────────

class _MarketMetricCard extends StatelessWidget {
  const _MarketMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 124,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _MarketBoardTemplate._grid,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _MarketBoardTemplate._panelEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const Spacer(),
          Text(
            label,
            style: const TextStyle(
              color: _MarketBoardTemplate._muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 6),
                child: child,
              ),
            ),
            child: Text(
              value,
              style: const TextStyle(
                color: _MarketBoardTemplate._ink,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 0.95,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Secondary read-out row ───────────────────────────────────────────────────

class _MarketReadoutTile extends StatelessWidget {
  const _MarketReadoutTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _MarketBoardTemplate._muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: _MarketBoardTemplate._muted,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: value == '—'
                ? _MarketBoardTemplate._muted
                : _MarketBoardTemplate._ink,
            fontSize: 16.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _MarketReadoutDivider extends StatelessWidget {
  const _MarketReadoutDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 11),
      child: Divider(height: 1, color: _MarketBoardTemplate._grid),
    );
  }
}

// ─── Real price-history sparkline ─────────────────────────────────────────────

class _MarketSparkline extends StatelessWidget {
  const _MarketSparkline({required this.history, required this.accent});

  final List<PropertyPricePoint> history;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sorted = [...history]..sort((a, b) => a.date.compareTo(b.date));
    final prices = sorted.map((p) => p.price).toList();
    final first = prices.first;
    final last = prices.last;
    final delta = last - first;
    final pct = first > 0 ? (delta / first * 100) : 0.0;
    final rising = delta > 0;
    final flat = delta == 0;
    final lineColor = flat
        ? _MarketBoardTemplate._muted
        : (rising ? _MarketBoardTemplate._up : _MarketBoardTemplate._down);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _MarketBoardTemplate._grid,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _MarketBoardTemplate._panelEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.marketBoardTemplateAd039ab0,
                style: TextStyle(
                  color: _MarketBoardTemplate._ink,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: lineColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      flat
                          ? Icons.trending_flat_rounded
                          : (rising
                              ? Icons.trending_up_rounded
                              : Icons.trending_down_rounded),
                      size: 15,
                      color: lineColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${rising ? '+' : ''}${pct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: lineColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 760),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => SizedBox(
              height: 56,
              width: double.infinity,
              child: CustomPaint(
                painter: _SparklinePainter(
                  prices: prices,
                  color: lineColor,
                  progress: t,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '₪${_compactNumber(first)}',
                style: const TextStyle(
                  color: _MarketBoardTemplate._muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '₪${_compactNumber(last)}',
                style: TextStyle(
                  color: lineColor,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.prices,
    required this.color,
    required this.progress,
  });

  final List<int> prices;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (prices.length < 2) return;
    final minP = prices.reduce((a, b) => a < b ? a : b).toDouble();
    final maxP = prices.reduce((a, b) => a > b ? a : b).toDouble();
    final span = (maxP - minP).abs() < 1 ? 1.0 : (maxP - minP);
    // RTL: oldest point on the right, newest on the left.
    final n = prices.length;
    final pts = <Offset>[];
    for (var i = 0; i < n; i++) {
      final x = size.width * (1 - i / (n - 1));
      final norm = (prices[i] - minP) / span;
      final y = size.height - norm * size.height;
      pts.add(Offset(x, y));
    }

    // Clip horizontally to `progress` for the draw-in animation (from right).
    // (Avoids `Path`, which collides with latlong2's `Path` in this library.)
    final clipLeft = size.width * (1 - progress);
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(clipLeft, 0, size.width, size.height));

    // Gradient area fill — triangulated from the baseline up to the line.
    final verts = <Offset>[];
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      verts
        ..add(Offset(a.dx, size.height))
        ..add(a)
        ..add(b)
        ..add(Offset(a.dx, size.height))
        ..add(b)
        ..add(Offset(b.dx, size.height));
    }
    canvas.drawVertices(
      Vertices(VertexMode.triangles, verts),
      BlendMode.dstOver,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );

    // Stroke line as a connected polyline.
    canvas.drawPoints(
      PointMode.polygon,
      pts,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    // Latest-value marker (leftmost point) once the line has drawn in.
    if (progress > 0.95) {
      final head = pts.first;
      canvas.drawCircle(head, 4.5, Paint()..color = color);
      canvas.drawCircle(
        head,
        4.5,
        Paint()
          ..color = _MarketBoardTemplate._grid
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.prices.length != prices.length;
}

// ─── Formatters (exclusive to this layout) ────────────────────────────────────

String _compactNumber(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value.toString();
}

/// Compact dwell-time read-out: seconds → "Ns" / "Nm" / "Nh".
String _compactDuration(int seconds, AppLocalizations l10n) {
  if (seconds < 60) return l10n.marketBoardTemplate2166e531(seconds);
  final minutes = seconds ~/ 60;
  if (minutes < 60) return l10n.marketBoardTemplate80126da3(minutes);
  final hours = minutes ~/ 60;
  return l10n.marketBoardTemplateAa8238e7(hours);
}
