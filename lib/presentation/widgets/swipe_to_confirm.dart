import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A reusable "slide to confirm" modal bottom sheet (RTL / Hebrew).
///
/// Shows a title + optional message and a draggable track. The user drags the
/// handle from the RIGHT to the LEFT (RTL reading direction) across the track to
/// confirm. Reaching the end pops `true` with a success haptic; cancelling or
/// dismissing pops `false`. Big, clear and friendly for older users.
///
/// Usage:
/// ```dart
/// final ok = await SwipeToConfirmSheet.show(
///   context,
///   title: 'לשלוח חוזה?',
///   message: 'האם אתה בטוח שאתה רוצה לשלוח חוזה לצד השני?',
/// );
/// if (ok) { /* proceed */ }
/// ```
class SwipeToConfirmSheet extends StatefulWidget {
  SwipeToConfirmSheet({
    super.key,
    required this.title,
    this.message,
    this.confirmLabel,
  });

  final String title;
  final String? message;
  final String? confirmLabel;

  /// Presents the sheet and resolves to `true` if the user slides to confirm,
  /// `false` if they cancel or dismiss.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    String? message,
    String? confirmLabel,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => SwipeToConfirmSheet(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
      ),
    );
    return result ?? false;
  }

  @override
  State<SwipeToConfirmSheet> createState() => _SwipeToConfirmSheetState();
}

class _SwipeToConfirmSheetState extends State<SwipeToConfirmSheet>
    with SingleTickerProviderStateMixin {
  // Drag progress, 0.0 (start, right) → 1.0 (end, left).
  double _progress = 0.0;
  bool _confirmed = false;

  static const double _trackHeight = 64.0;
  static const double _handleSize = 56.0;
  static const double _padding = 4.0;

  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  // Distance (px) the handle can travel inside the track.
  double _travel(double trackWidth) =>
      trackWidth - _handleSize - (_padding * 2);

  void _onDragUpdate(DragUpdateDetails d, double trackWidth) {
    if (_confirmed) return;
    final travel = _travel(trackWidth);
    if (travel <= 0) return;
    // RTL: dragging LEFT (negative dx) increases progress.
    setState(() {
      _progress = (_progress - d.delta.dx / travel).clamp(0.0, 1.0);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_confirmed) return;
    if (_progress >= 0.9) {
      _complete();
    } else {
      _snapBack();
    }
  }

  void _snapBack() {
    final anim = Tween<double>(begin: _progress, end: 0.0).animate(
      CurvedAnimation(parent: _snap, curve: Curves.easeOut),
    );
    void listener() => setState(() => _progress = anim.value);
    anim.addListener(listener);
    _snap.forward(from: 0).whenComplete(() {
      anim.removeListener(listener);
      _snap.reset();
    });
  }

  void _complete() {
    setState(() {
      _progress = 1.0;
      _confirmed = true;
    });
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Directionality.of(context),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 14, 20, 20 + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grab handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (widget.message != null && widget.message!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                widget.message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) =>
                  _buildTrack(constraints.maxWidth),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                AppLocalizations.of(context)!.swipeToConfirmA7c55a8d,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrack(double trackWidth) {
    final travel = _travel(trackWidth);
    // In RTL the handle starts at the right edge and moves left.
    final right = _padding + (_progress * travel);
    final fillColor = _confirmed ? AppColors.success : AppColors.primary;

    return GestureDetector(
      onHorizontalDragUpdate: (d) => _onDragUpdate(d, trackWidth),
      onHorizontalDragEnd: _onDragEnd,
      child: Container(
        height: _trackHeight,
        decoration: BoxDecoration(
          color: AppColors.primaryLight2,
          borderRadius: BorderRadius.circular(_trackHeight / 2),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Stack(
          children: [
            // Filled portion (grows from the right as the user drags left).
            Positioned(
              top: _padding,
              bottom: _padding,
              right: _padding,
              width: (_handleSize + _progress * travel)
                  .clamp(0.0, trackWidth - _padding * 2),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: fillColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(_trackHeight / 2),
                ),
              ),
            ),
            // Label
            Center(
              child: Opacity(
                opacity: (1.0 - _progress * 1.6).clamp(0.0, 1.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        widget.confirmLabel ??
                            AppLocalizations.of(context)!.swipeToConfirm55ebef41,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      // Chevron points left (drag direction in RTL).
                      Icons.keyboard_double_arrow_left_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
            // Draggable handle
            Positioned(
              top: _padding,
              right: right,
              child: Container(
                width: _handleSize,
                height: _handleSize,
                decoration: BoxDecoration(
                  color: fillColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: fillColor.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  _confirmed
                      ? Icons.check_rounded
                      : Icons.keyboard_arrow_left_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
