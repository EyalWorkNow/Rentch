import 'dart:ui';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/ui/platform_fx.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/explore_screen.dart';
import 'package:dating_app/presentation/screens/matches_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

/// The merged landlord "לקוחות" screen: a single tab that hosts BOTH the
/// candidate swipe deck (מועמדים) and the conversations list (הודעות) behind a
/// 2-segment glass toggle. Both children are kept alive via an [IndexedStack]
/// so swiping/scrolling state survives a toggle.
class LeadsInboxScreen extends StatefulWidget {
  const LeadsInboxScreen({super.key, this.initialSegment = 0});

  /// Which segment to open on first build — 0 = מועמדים, 1 = הודעות.
  final int initialSegment;

  @override
  State<LeadsInboxScreen> createState() => _LeadsInboxScreenState();
}

class _LeadsInboxScreenState extends State<LeadsInboxScreen> {
  late int _selected = widget.initialSegment.clamp(0, 1);

  @override
  void initState() {
    super.initState();
    // SCHED-4: process viewing confirmations globally the moment the landlord
    // opens the merged לקוחות screen — so a tenant's confirm becomes a booking +
    // reminder + dashboard entry even if the landlord never opens that specific
    // thread. Idempotent + fail-soft (guarded inside the provider).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DatingProvider>().processViewingConfirms();
    });
  }

  void _select(int index) {
    if (index == _selected) {
      HapticFeedback.selectionClick();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DatingProvider>();
    final leadsCount = provider.ownerLeads.length;
    final unseenCount = provider.unseenMatchCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Center(
                child: _SegmentToggle(
                  selected: _selected,
                  candidatesBadge: leadsCount,
                  messagesBadge: unseenCount,
                  onSelect: _select,
                ),
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _selected,
              children: [
                ExploreScreen(
                  embedded: true,
                  // NAV-B: the candidates empty-state "עבור לשיחות" flips to the
                  // הודעות segment instead of pushing a chrome-less screen.
                  onGoToMessages: () => _select(1),
                ),
                const MatchesScreen(embedded: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A 2-segment glass pill with a sliding gradient thumb, press-scale and per
/// segment count badges — reproduces the discover_screen selector look.
class _SegmentToggle extends StatefulWidget {
  const _SegmentToggle({
    required this.selected,
    required this.candidatesBadge,
    required this.messagesBadge,
    required this.onSelect,
  });

  final int selected;
  final int candidatesBadge;
  final int messagesBadge;
  final ValueChanged<int> onSelect;

  @override
  State<_SegmentToggle> createState() => _SegmentToggleState();
}

class _SegmentToggleState extends State<_SegmentToggle> {
  int? _pressed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 40;
        final width = maxWidth.clamp(0.0, 360.0);
        const pad = 5.0;
        final inner = (width - pad * 2).clamp(0.0, double.infinity);
        final segW = inner / 2;
        // Visual order left→right: [מועמדים, הודעות]. Segment 0 sits on the left.
        final thumbLeft = widget.selected == 0 ? 0.0 : segW;

        return SizedBox(
          width: width,
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: AppColors.slate100.withValues(alpha: 0.85),
              border: Border.all(
                color: AppColors.slate200.withValues(alpha: 0.8),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: PlatformFx.blurSigma(14),
                  sigmaY: PlatformFx.blurSigma(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(pad),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    // Clip the sliding thumb's glow to the pill (Android/Impeller
                    // doesn't contain child shadows via an ancestor ClipRRect over
                    // a BackdropFilter — same fix as the discover _PillSelector).
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          left: thumbLeft,
                          width: segW,
                          top: 0,
                          bottom: 0,
                          // NOT const: the thumb's gradient is the swappable
                          // accent, and a const widget never rebuilds — so it
                          // would freeze on the accent value from first build.
                          child: _Thumb(),
                        ),
                        Row(
                          children: [
                            SizedBox(
                              width: segW,
                              child: _segment(
                                index: 0,
                                icon: IconsaxPlusLinear.profile_2user,
                                label: 'מועמדים',
                                badge: widget.candidatesBadge,
                                isSelected: widget.selected == 0,
                              ),
                            ),
                            SizedBox(
                              width: segW,
                              child: _segment(
                                index: 1,
                                icon: IconsaxPlusLinear.message,
                                label: 'הודעות',
                                badge: widget.messagesBadge,
                                isSelected: widget.selected == 1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _segment({
    required int index,
    required IconData icon,
    required String label,
    required int badge,
    required bool isSelected,
  }) {
    final inactiveColor = AppColors.textSecondary.withValues(alpha: 0.84);
    final pressed = _pressed == index;
    final selectedShadow = [
      Shadow(
        color: AppColors.navy.withValues(alpha: 0.22),
        offset: const Offset(0, 1),
        blurRadius: 5,
      ),
    ];
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = index),
        onTapUp: (_) => setState(() => _pressed = null),
        onTapCancel: () => setState(() => _pressed = null),
        onTap: () => widget.onSelect(index),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          scale: pressed ? 0.93 : (isSelected ? 1.03 : 1),
          // Inset so the label+icon stay INSIDE the coloured thumb on Android too.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    scale: isSelected ? 1.14 : 1,
                    child: Icon(
                      icon,
                      size: 17,
                      color: isSelected ? Colors.white : inactiveColor,
                      shadows: isSelected ? selectedShadow : null,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1,
                      fontWeight:
                          isSelected ? FontWeight.w900 : FontWeight.w800,
                      color: isSelected ? Colors.white : inactiveColor,
                      shadows: isSelected ? selectedShadow : null,
                    ),
                  ),
                  if (badge > 0) ...[
                    const SizedBox(width: 6),
                    _CountBadge(count: badge, onSelected: isSelected),
                  ],
                ],
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }
}

/// The small rounded count pill shown next to a segment label.
class _CountBadge extends StatelessWidget {
  _CountBadge({required this.count, required this.onSelected});

  final int count;
  final bool onSelected;

  @override
  Widget build(BuildContext context) {
    final bg = onSelected ? Colors.white : AppColors.coral;
    final fg = onSelected ? AppColors.primary : Colors.white;
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10,
          height: 1,
          fontWeight: FontWeight.w900,
          color: fg,
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  // Non-const constructor on purpose: this widget paints the swappable brand
  // accent, so it must be allowed to rebuild when the accent changes.
  _Thumb();

  @override
  Widget build(BuildContext context) {
    final isBroker = AppColors.isBrokerAccent;
    final gradientColors = isBroker
        ? [AppColors.primaryLight, AppColors.primary]
        : [
            AppColors.primaryLight,
            AppColors.primary,
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.24),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(23),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.30),
                    Colors.white.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.07),
                  ],
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 6,
            start: 12,
            width: 38,
            height: 14,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.48),
                    Colors.white.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
