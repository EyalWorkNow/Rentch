import 'package:dating_app/presentation/features/assistant/erik_design.dart';
import 'package:dating_app/presentation/features/assistant/erik_presence.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// ───────────────────────────────────────────────────────────────────────────
/// Erik VOICE-CALL — the centerpiece.
///
/// A full, immersive hands-free call experience: the large living presence orb,
/// a live audio visualizer, the running transcript, unmistakable state feedback
/// (listening vs Erik speaking), and a clear control bar (mute Erik's voice /
/// switch to keyboard / hang up).
///
/// This is PURE PRESENTATION. Every piece of state and every action is passed in
/// from AssistantScreen, so all the voice/STT/TTS/Gemini-Live wiring stays
/// exactly where it lives. The widget renders; the screen decides.
/// ───────────────────────────────────────────────────────────────────────────
class ErikVoiceCall extends StatelessWidget {
  const ErikVoiceCall({
    super.key,
    required this.clock,
    required this.state,
    required this.connecting,
    required this.callActive,
    required this.statusLine,
    required this.transcript,
    required this.soundLevel,
    required this.voiceOn,
    required this.onHangUp,
    required this.onToggleVoice,
    required this.onSwitchToText,
    required this.onTapOrb,
  });

  /// A shared 0..1 breathing clock (the screen's pulse controller value).
  final double clock;
  final ErikState state;
  final bool connecting;

  /// True while a real-time live call is connected/active.
  final bool callActive;

  final String statusLine;

  /// The live partial transcript to surface large under the orb (user OR Erik).
  final String transcript;

  final ValueListenable<double> soundLevel;

  /// Whether Erik's spoken replies are on (controls the mute button look).
  final bool voiceOn;

  final VoidCallback onHangUp;
  final VoidCallback onToggleVoice;
  final VoidCallback onSwitchToText;
  final VoidCallback onTapOrb;

  Color get _accent => ErikTokens.accent;

  @override
  Widget build(BuildContext context) {
    final speaking = state == ErikState.speaking;
    final listening = state == ErikState.listening;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: Column(
        children: [
          _statusChip(speaking: speaking, listening: listening),
          const Spacer(flex: 2),
          // ── The hero presence orb ──────────────────────────────────────────
          GestureDetector(
            onTap: onTapOrb,
            behavior: HitTestBehavior.opaque,
            child: ErikPresence(
              size: 210,
              state: state,
              accent: ErikTokens.accent,
              accentGlow: ErikTokens.accentGlow,
              soundLevel: soundLevel,
            ),
          ),
          const SizedBox(height: ErikTokens.s4),
          // ── Big, clear state headline ───────────────────────────────────────
          AnimatedSwitcher(
            duration: ErikTokens.mBase,
            child: Text(
              statusLine,
              key: ValueKey(statusLine),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: state == ErikState.idle ? ErikTokens.inkSoft : _accent,
                fontSize: 23,
                fontWeight: FontWeight.w900,
                height: 1.2,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: ErikTokens.s3),
          // ── Live transcript caption ─────────────────────────────────────────
          _transcriptArea(),
          const Spacer(flex: 2),
          // ── Live audio visualizer ───────────────────────────────────────────
          ErikWaveform(
            t: clock,
            level: soundLevel.value,
            active: callActive && !connecting,
            color: _accent,
            height: 60,
          ),
          const SizedBox(height: ErikTokens.s6),
          // ── Control bar ─────────────────────────────────────────────────────
          _controlBar(),
          const SizedBox(height: ErikTokens.s2),
        ],
      ),
    );
  }

  Widget _statusChip({required bool speaking, required bool listening}) {
    final live = callActive && !connecting;
    final label = connecting
        ? 'מתחבר...'
        : live
            ? 'שיחה חיה'
            : 'מוכן לשיחה';
    final dotColor = connecting
        ? ErikTokens.muted
        : live
            ? ErikTokens.online
            : ErikTokens.muted;
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
          Text(label,
              style: TextStyle(
                color: ErikTokens.inkSoft,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              )),
        ],
      ),
    );
  }

  Widget _transcriptArea() {
    final text = transcript.trim();
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64, maxHeight: 132),
      child: SingleChildScrollView(
        reverse: true,
        child: AnimatedSwitcher(
          duration: ErikTokens.mFast,
          child: Text(
            text.isEmpty
                ? (state == ErikState.speaking
                    ? 'אריק עונה לך...'
                    : 'דבר חופשי — אני מקשיב, ועונה בקול. אפשר גם לקטוע אותי באמצע.')
                : text,
            key: ValueKey(text.isEmpty ? 'hint' : text),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: text.isEmpty ? ErikTokens.muted : ErikTokens.ink,
              fontSize: text.isEmpty ? 16 : 19,
              height: 1.5,
              fontWeight: text.isEmpty ? FontWeight.w600 : FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _controlBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mute Erik's voice (real: toggles voiceReplies + stops speaking).
        _CallButton(
          icon: voiceOn
              ? IconsaxPlusBold.volume_high
              : IconsaxPlusLinear.volume_slash,
          label: voiceOn ? 'קול פעיל' : 'מושתק',
          color: ErikTokens.inkSoft,
          background: ErikTokens.glassHi,
          onTap: onToggleVoice,
        ),
        const SizedBox(width: 26),
        // Hang up — the unmistakable primary control.
        _CallButton(
          icon: callActive
              ? IconsaxPlusBold.call_slash
              : IconsaxPlusBold.microphone_2,
          label: callActive ? 'סיים שיחה' : 'התחל שיחה',
          color: Colors.white,
          background: callActive ? ErikTokens.danger : ErikTokens.accent,
          big: true,
          glow: true,
          clock: clock,
          onTap: onHangUp,
        ),
        const SizedBox(width: 26),
        // Switch to typing.
        _CallButton(
          icon: IconsaxPlusLinear.keyboard,
          label: 'מקלדת',
          color: ErikTokens.inkSoft,
          background: ErikTokens.glassHi,
          onTap: onSwitchToText,
        ),
      ],
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
    final dim = big ? 76.0 : 58.0;
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
              border: glow
                  ? null
                  : Border.all(color: ErikTokens.line, width: 1.2),
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
            child: Icon(icon, color: color, size: big ? 30 : 24),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: ErikTokens.muted,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _BreathingDot extends StatelessWidget {
  const _BreathingDot({required this.color, required this.clock, required this.on});
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
