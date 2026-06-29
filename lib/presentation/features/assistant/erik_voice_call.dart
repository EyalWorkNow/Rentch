import 'dart:ui';

import 'package:dating_app/presentation/features/assistant/erik_design.dart';
import 'package:dating_app/presentation/features/assistant/erik_presence.dart';
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

  @override
  Widget build(BuildContext context) {
    final idle = state == ErikState.idle && !callActive;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
        child: Column(
          children: [
            _statusChip(),
            const Spacer(flex: 3),

            // ── The orb — the centerpiece. Tap to start / stop the talk. ──────
            GestureDetector(
              onTap: onTapOrb,
              behavior: HitTestBehavior.opaque,
              child: ErikPresence(
                size: 216,
                state: state,
                accent: ErikTokens.accent,
                accentGlow: ErikTokens.accentGlow,
                soundLevel: soundLevel,
              ),
            ),

            const SizedBox(height: ErikTokens.s3),

            // ── Status line ───────────────────────────────────────────────────
            AnimatedSwitcher(
              duration: ErikTokens.mBase,
              child: Text(
                statusLine,
                key: ValueKey(statusLine),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: idle ? ErikTokens.inkSoft : _accent,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                  letterSpacing: 0.2,
                ),
              ),
            ),

            const SizedBox(height: ErikTokens.s4),

            // ── Live waveform ─────────────────────────────────────────────────
            ErikWaveform(
              t: clock,
              level: soundLevel.value,
              active: callActive && !connecting,
              color: _accent,
              height: 48,
            ),

            const Spacer(flex: 2),

            // ── Minimal reply area (Erik's latest words + user's last line) ────
            _replyArea(idle: idle),

            const Spacer(flex: 3),

            // ── Minimal control row: mic · keyboard · end ─────────────────────
            _controls(),
            const SizedBox(height: ErikTokens.s1),
          ],
        ),
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

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 96, maxHeight: 188),
      child: SingleChildScrollView(
        reverse: true,
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mute / unmute Erik's voice.
        _CallButton(
          icon: voiceOn
              ? IconsaxPlusBold.volume_high
              : IconsaxPlusLinear.volume_slash,
          label: voiceOn ? 'קול פעיל' : 'מושתק',
          color: ErikTokens.inkSoft,
          background: ErikTokens.glassHi,
          onTap: onToggleVoice,
        ),
        const SizedBox(width: 22),
        // The big primary mic — start / stop the conversation (same as the orb).
        _CallButton(
          icon: callActive
              ? IconsaxPlusBold.microphone_2
              : IconsaxPlusBold.microphone_2,
          label: callActive ? 'מקשיב...' : 'דבר',
          color: Colors.white,
          background: callActive ? ErikTokens.danger : ErikTokens.accent,
          big: true,
          glow: true,
          clock: clock,
          onTap: onToggleMic,
        ),
        const SizedBox(width: 22),
        // Keyboard fallback — reveal the text composer.
        _CallButton(
          icon: IconsaxPlusLinear.keyboard,
          label: 'מקלדת',
          color: ErikTokens.inkSoft,
          background: ErikTokens.glassHi,
          onTap: onOpenKeyboard,
        ),
        const SizedBox(width: 22),
        // End / close.
        _CallButton(
          icon: IconsaxPlusBold.close_circle,
          label: 'סגור',
          color: ErikTokens.inkSoft,
          background: ErikTokens.glassHi,
          onTap: onClose,
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
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
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
                        background: const Color(0xFFF1F5F8),
                        foreground: const Color(0xFF5B7A99),
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
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: dim,
            height: dim,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: background,
              border:
                  glow ? null : Border.all(color: ErikTokens.line, width: 1.2),
              boxShadow: glow
                  ? [
                      BoxShadow(
                        color: background.withValues(alpha: 0.40 + 0.16 * t),
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
        const SizedBox(height: 8),
        Text(
          label,
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
