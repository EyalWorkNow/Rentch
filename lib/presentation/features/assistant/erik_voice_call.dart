import 'dart:ui';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/ui/platform_fx.dart';

import 'package:dating_app/presentation/features/assistant/erik_design.dart';
import 'package:dating_app/presentation/features/assistant/erik_presence.dart';
import 'package:dating_app/presentation/widgets/liquid_glass_orb.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// ───────────────────────────────────────────────────────────────────────────
/// Erik ORB STAGE — the whole interface.
///
/// A calm, immersive, voice-first screen built around ONE large glowing orb in
/// the centre (Siri / ChatGPT-voice style). The orb is the centerpiece and the
/// only thing a user really needs to touch:
///   • tap the orb → start / stop the conversation
///   • a short STATUS line + live WAVEFORM sit just under it
///   • a minimal REPLY area shows Erik's latest words (and the user's last line)
///   • a minimal control row: mic toggle · keyboard (text fallback) · end
///
/// This is PURE PRESENTATION. Every callback and value is supplied by
/// AssistantScreen, so all the STT / TTS / Gemini-Live wiring stays exactly
/// where it lives. The widget renders; the screen decides.
/// ───────────────────────────────────────────────────────────────────────────
class ErikOrbStage extends StatelessWidget {
  const ErikOrbStage({
    super.key,
    required this.clock,
    required this.state,
    required this.connecting,
    required this.callActive,
    required this.statusLine,
    required this.erikReply,
    required this.userLine,
    required this.soundLevel,
    required this.voiceOn,
    required this.onTapOrb,
    required this.onToggleMic,
    required this.onOpenKeyboard,
    required this.onToggleVoice,
    required this.onClose,
  });

  /// Shared 0..1 breathing clock (the screen's pulse controller value).
  final double clock;
  final ErikState state;

  /// True while connecting a real-time live session.
  final bool connecting;

  /// True while a voice conversation is active (live OR hands-free / mic on).
  final bool callActive;

  /// Short status line under the orb ("מקשיב לך…", "חושב…", "אריק מדבר…", …).
  final String statusLine;

  /// Erik's latest short reply (surfaced as minimal text, not a full log).
  final String erikReply;

  /// The user's last utterance (small, secondary).
  final String userLine;

  final ValueListenable<double> soundLevel;

  /// Whether Erik's spoken replies are on (drives the mute control look).
  final bool voiceOn;

  /// Tap the orb → toggle the conversation (the existing live/hands-free toggle).
  final VoidCallback onTapOrb;

  /// Mic control → the existing mic toggle.
  final VoidCallback onToggleMic;

  /// ⌨ → reveal the text composer (fallback to typing).
  final VoidCallback onOpenKeyboard;

  /// Mute / unmute Erik's voice.
  final VoidCallback onToggleVoice;

  /// End / close the conversation.
  final VoidCallback onClose;

  Color get _accent => ErikTokens.accent;

  // Maps Erik's state + mic level to the liquid-glass orb's activity (0..1).
  double _orbLevel(double lvl) {
    switch (state) {
      case ErikState.listening:
        return (0.25 + lvl * 0.75).clamp(0.0, 1.0);
      case ErikState.speaking:
        return 0.85;
      case ErikState.thinking:
        return 0.45;
      case ErikState.idle:
        return 0.18;
    }
  }

  @override
  Widget build(BuildContext context) {
    final idle = state == ErikState.idle && !callActive;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The screen must fit on a short phone AND breathe on a tall one, so
          // the orb and the gaps scale with the available height rather than
          // relying on fixed sizes that overflow.
          final h = constraints.maxHeight;
          final w = constraints.maxWidth;

          // Orb diameter scales with the smaller of width/height; the presence
          // widget paints inside a field 1.85× this, so we cap so the field
          // never dominates a small screen.
          final orbSize = (h * 0.30)
              .clamp(132.0, 216.0)
              .clamp(0.0, (w - 24) / 1.85)
              .toDouble();

          // Vertical rhythm scales gently with height (tight on small phones).
          final gap = (h * 0.02).clamp(8.0, 22.0).toDouble();

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(
              children: [
                _statusChip(),
                SizedBox(height: gap),

                // ── The orb — the centerpiece. Tap to start / stop the talk. ──
                // FittedBox lets the orb shrink to whatever vertical room the
                // Flexible region offers, so its glow-field never overflows on a
                // short screen (or with the keyboard / a panel pushing up).
                Flexible(
                  flex: 6,
                  child: Center(
                    child: GestureDetector(
                      onTap: onTapOrb,
                      behavior: HitTestBehavior.opaque,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        // Same liquid-glass presence as אתי (shared widget).
                        child: ValueListenableBuilder<double>(
                          valueListenable: soundLevel,
                          builder: (_, lvl, __) => LiquidGlassOrb(
                            size: orbSize,
                            level: _orbLevel(lvl),
                            speaking: state == ErikState.speaking,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Status line ───────────────────────────────────────────────
                AnimatedSwitcher(
                  duration: ErikTokens.mBase,
                  child: Text(
                    statusLine,
                    key: ValueKey(statusLine),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: idle ? ErikTokens.inkSoft : _accent,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),

                SizedBox(height: gap),

                // ── Live waveform ─────────────────────────────────────────────
                ErikWaveform(
                  t: clock,
                  level: soundLevel.value,
                  active: callActive && !connecting,
                  color: _accent,
                  height: 44,
                ),

                // ── Minimal reply area (Erik's latest words + user's last line)─
                Flexible(
                  flex: 5,
                  child: Center(child: _replyArea(idle: idle)),
                ),

                SizedBox(height: gap),

                // ── Minimal control row: mic · keyboard · end ─────────────────
                _controls(),
                const SizedBox(height: ErikTokens.s1),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statusChip() {
    final live = callActive && !connecting;
    final label = connecting
        ? 'מתחבר...'
        : live
            ? 'מקשיב — דבר חופשי'
            : 'אריק · מוכן לשיחה';
    final dotColor = live ? ErikTokens.online : ErikTokens.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: ErikTokens.glassHi,
        borderRadius: BorderRadius.circular(ErikTokens.rPill),
        border: Border.all(color: ErikTokens.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BreathingDot(color: dotColor, clock: clock, on: live || connecting),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: ErikTokens.inkSoft,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  /// A small, calm area — Erik's latest reply (primary) and the user's last
  /// utterance (secondary). Minimal: voice is the main channel.
  Widget _replyArea({required bool idle}) {
    final erik = erikReply.trim();
    final user = userLine.trim();

    final String erikText = erik.isNotEmpty
        ? erik
        : idle
            ? 'גע בכדור כדי לדבר איתי, או הקש ⌨ כדי לכתוב.'
            : state == ErikState.thinking
                ? '...'
                : state == ErikState.speaking
                    ? 'אריק עונה לך...'
                    : 'אני מקשיב — דבר חופשי על הדירה.';

    return SingleChildScrollView(
      reverse: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (user.isNotEmpty) ...[
              _UserLine(text: user),
              const SizedBox(height: ErikTokens.s3),
            ],
            AnimatedSwitcher(
              duration: ErikTokens.mFast,
              child: Text(
                erikText,
                key: ValueKey(erikText),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: erik.isEmpty ? ErikTokens.muted : ErikTokens.ink,
                  fontSize: erik.isEmpty ? 16.5 : 19,
                  height: 1.5,
                  fontWeight: erik.isEmpty ? FontWeight.w600 : FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    // Equal-width cells (Expanded) so the row never overflows on narrow phones;
    // the big mic stays visually centred and every label sits on one baseline.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mute / unmute Erik's voice.
        Expanded(
          child: _CallButton(
            icon: voiceOn
                ? IconsaxPlusBold.volume_high
                : IconsaxPlusLinear.volume_slash,
            label: voiceOn ? 'קול פעיל' : 'מושתק',
            color: ErikTokens.inkSoft,
            background: ErikTokens.glassHi,
            onTap: onToggleVoice,
          ),
        ),
        // The big primary mic — start / stop the conversation (same as the orb).
        Expanded(
          child: _CallButton(
            icon: IconsaxPlusBold.microphone_2,
            label: callActive ? 'מקשיב...' : 'דבר',
            color: Colors.white,
            background: callActive ? ErikTokens.danger : ErikTokens.accent,
            big: true,
            glow: true,
            clock: clock,
            onTap: onToggleMic,
          ),
        ),
        // Keyboard fallback — reveal the text composer.
        Expanded(
          child: _CallButton(
            icon: IconsaxPlusLinear.keyboard,
            label: 'מקלדת',
            color: ErikTokens.inkSoft,
            background: ErikTokens.glassHi,
            onTap: onOpenKeyboard,
          ),
        ),
        // End / close.
        Expanded(
          child: _CallButton(
            icon: IconsaxPlusBold.close_circle,
            label: 'סגור',
            color: ErikTokens.inkSoft,
            background: ErikTokens.glassHi,
            onTap: onClose,
          ),
        ),
      ],
    );
  }
}

/// The minimal text composer revealed by the ⌨ button — a fallback to typing.
/// It calls back into the screen's existing `_send`.
class ErikTextComposer extends StatelessWidget {
  const ErikTextComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onClose,
    required this.onAddMedia,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSend;
  final VoidCallback onClose;
  final VoidCallback onAddMedia;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        // sigma reduced 22→14: this glass sits over the CONTINUOUSLY animating
        // orb, so the blur re-samples the layer below every frame — a lower sigma
        // is a materially cheaper per-frame convolution with no visible loss.
        filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(14), sigmaY: PlatformFx.blurSigma(14)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: ErikTokens.bgVeil.withValues(alpha: 0.96),
            border: const Border(top: BorderSide(color: ErikTokens.lineStrong)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'כתוב לאריק',
                      style: TextStyle(
                        color: ErikTokens.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: onClose,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(IconsaxPlusLinear.arrow_down_1,
                            color: Colors.white70, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      _ComposerCircleButton(
                        icon: IconsaxPlusBold.add,
                        background: AppColors.slate100,
                        foreground: AppColors.textSecondary,
                        onTap: onAddMedia,
                        size: 46,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          textInputAction: TextInputAction.send,
                          style: const TextStyle(
                            fontSize: 17,
                            color: ErikTokens.navyText,
                            fontWeight: FontWeight.w600,
                          ),
                          cursorColor: ErikTokens.accent,
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText: 'כתוב הודעה...',
                            hintStyle: TextStyle(
                                fontSize: 16, color: Color(0x8C5B7A99)),
                            filled: false,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 11),
                            border: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            enabledBorder: InputBorder.none,
                          ),
                          onSubmitted: onSend,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, _) {
                          final hasText = value.text.trim().isNotEmpty;
                          return _ComposerCircleButton(
                            icon: IconsaxPlusBold.send_1,
                            background: ErikTokens.accent,
                            foreground: Colors.white,
                            onTap: hasText ? () => onSend(controller.text) : () {},
                            useGradient: true,
                            size: 50,
                          );
                        },
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
  }
}

class _UserLine extends StatelessWidget {
  const _UserLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: ErikTokens.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(ErikTokens.rPill),
        border: Border.all(color: ErikTokens.accent.withValues(alpha: 0.30)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: ErikTokens.accent,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
    required this.onTap,
    this.big = false,
    this.glow = false,
    this.clock = 0,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;
  final VoidCallback onTap;
  final bool big;
  final bool glow;
  final double clock;

  @override
  Widget build(BuildContext context) {
    final dim = big ? 76.0 : 56.0;
    final t = clock;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Fixed 76-high slot keeps every label on one baseline regardless of
        // whether the circle is the big mic (76) or a small control (56).
        SizedBox(
          height: 76,
          child: Center(
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: Ink(
                  width: dim,
                  height: dim,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: background,
                    border: glow
                        ? null
                        : Border.all(color: ErikTokens.line, width: 1.2),
                    boxShadow: glow
                        ? [
                            BoxShadow(
                              color:
                                  background.withValues(alpha: 0.40 + 0.16 * t),
                              blurRadius: 26 + 10 * t,
                              spreadRadius: 1 + 1.5 * t,
                              offset: const Offset(0, 10),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(icon, color: color, size: big ? 30 : 23),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: ErikTokens.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ComposerCircleButton extends StatelessWidget {
  const _ComposerCircleButton({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.useGradient = false,
    this.size = 50.0,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;
  final bool useGradient;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: useGradient ? null : background,
          gradient: useGradient
              ? LinearGradient(
                  colors: [ErikTokens.accentGlow, ErikTokens.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          boxShadow: useGradient
              ? [
                  BoxShadow(
                    color: ErikTokens.accent.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Icon(icon, color: foreground, size: size * 0.46),
      ),
    );
  }
}

class _BreathingDot extends StatelessWidget {
  const _BreathingDot(
      {required this.color, required this.clock, required this.on});
  final Color color;
  final double clock;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: on
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.6 * clock),
                  blurRadius: 4 + 4 * clock,
                  spreadRadius: 0.5 + 1.5 * clock,
                ),
              ]
            : null,
      ),
    );
  }
}
