import 'dart:async';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/assistant_live_service.dart' show LiveStatus;
import 'package:dating_app/core/services/openai_realtime_service.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/widgets/liquid_glass_orb.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// Full-screen LIVE (speech-to-speech) conversation with אתי over Gemini Live.
///
/// Unlike the turn-based [AtiVoiceScreen] (hold-to-talk → STT → LLM → TTS, each a
/// trans-Atlantic round-trip), this streams audio both ways over ONE direct
/// WebSocket to Gemini — server VAD, barge-in, sub-second replies. The mic is
/// always open; the user just talks. When אתי has enough she calls search_listings,
/// which [onSearch] runs on-device (real ranking + cards in the chat behind), and
/// she voices the returned summary.
///
/// Gated behind AppConfig.atiLiveVoice. If the live session can't connect, the
/// caller falls back to the turn-based screen — this widget pops and calls
/// [onConnectFailed].
class AtiLiveVoiceScreen extends StatefulWidget {
  const AtiLiveVoiceScreen({
    super.key,
    required this.onSearch,
    required this.onConnectFailed,
    this.onUserUtterance,
    this.criteria = const [],
  });

  /// Fired once per completed user turn with the final transcript. The live
  /// path used to paint the transcript on screen and DROP it — so the chat's
  /// conversation state, cohort signals and lifestyle rules never saw what the
  /// user said by voice. The host wires this back into the same pipeline text
  /// messages flow through.
  final void Function(String utterance)? onUserUtterance;

  /// Runs the real on-device search for a search_listings tool-call; returns how
  /// many listings matched + a short spoken summary for אתי.
  final Future<({int count, String summary})> Function(Map<String, dynamic> args)
      onSearch;

  /// The live session failed to connect — the caller should open the turn-based
  /// voice screen instead so the user is never left without a voice option.
  final VoidCallback onConnectFailed;

  final List<String> criteria;

  @override
  State<AtiLiveVoiceScreen> createState() => _AtiLiveVoiceScreenState();
}

class _AtiLiveVoiceScreenState extends State<AtiLiveVoiceScreen> {
  final OpenAiRealtimeService _live = OpenAiRealtimeService(mode: 'tenant_search');
  LiveStatus _status = LiveStatus.connecting;
  String _userText = '';
  String _atiText = ''; // empty until the first real chunk arrives
  int _resultCount = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _live
      ..onStatus = (s) {
        if (mounted) setState(() => _status = s);
      }
      ..onUserText = (t) {
        // Gemini streams input transcription in chunks; show the latest words.
        if (mounted) setState(() => _userText = t.trim());
      }
      ..onErikText = (t) {
        if (mounted) {
          setState(() {
            // First chunk of a new reply resets the caption; rest appends.
            _atiText = _status == LiveStatus.speaking && _atiText.isNotEmpty
                ? '$_atiText$t'
                : t;
          });
        }
      }
      ..onTurnComplete = () {
        final utterance = _userText.trim();
        if (utterance.isNotEmpty) widget.onUserUtterance?.call(utterance);
        if (mounted) setState(() => _userText = '');
      }
      ..onSearchListings = (args) async {
        final r = await widget.onSearch(args);
        if (mounted) setState(() => _resultCount = r.count);
        return r.summary;
      }
      ..onError = (msg) {
        if (_failed) return;
        _failed = true;
        // Connect/stream failure → hand back to the turn-based flow. Do NOT pop
        // here — onConnectFailed does a single pushReplacement, so the user sees
        // ONE transition, not this screen sliding down and the fallback sliding
        // back up (the "rises and falls in 2 steps").
        if (mounted) widget.onConnectFailed();
      };
    _live.connect();
  }

  @override
  void dispose() {
    _live.dispose();
    super.dispose();
  }

  String get _statusLabel {
    final l10n = AppLocalizations.of(context)!;
    switch (_status) {
      case LiveStatus.connecting:
        return l10n.atiLiveVoiceScreenA7587542;
      case LiveStatus.listening:
        return l10n.atiLiveVoiceScreenAc995fe3;
      case LiveStatus.speaking:
        return l10n.atiLiveVoiceScreen746981e0;
      case LiveStatus.error:
        return l10n.atiLiveVoiceScreenAa5a9e29;
      case LiveStatus.idle:
      case LiveStatus.closed:
        return l10n.atiLiveVoiceScreenC21710c8;
    }
  }

  double get _activity {
    switch (_status) {
      case LiveStatus.speaking:
        return 0.9;
      case LiveStatus.listening:
        return 0.4;
      default:
        return 0.2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final atiDisplay =
        _atiText.isNotEmpty ? _atiText : l10n.atiLiveVoiceScreenA7587542;
    final caption = _userText.isNotEmpty ? _userText : atiDisplay;
    final isUser = _userText.isNotEmpty;
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.35),
              radius: 1.25,
              colors: [AppColors.navy, AppColors.ink, Color(0xFF03080E)],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(IconsaxPlusLinear.arrow_down_1,
                        color: Colors.white70, size: 32),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
                if (widget.criteria.isNotEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in widget.criteria)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 13, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.14)),
                            ),
                            child: Text(c,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                  ),
                const Spacer(),
                _statusPill(),
                const SizedBox(height: 14),
                LiquidGlassOrb(
                  size: 175,
                  level: _activity,
                  speaking: _status == LiveStatus.speaking,
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      caption,
                      key: ValueKey(caption),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isUser ? Colors.white70 : Colors.white,
                        fontSize: 19,
                        height: 1.5,
                        fontStyle: isUser ? FontStyle.italic : FontStyle.normal,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                if (_resultCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 13),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            Icon(IconsaxPlusBold.home_2,
                                color: AppColors.primary, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                  l10n.atiLiveVoiceScreen9a60c4a8(
                                      _resultCount),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                            ),
                            Text(l10n.atiLiveVoiceScreen193535e0,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700)),
                            const Icon(IconsaxPlusLinear.arrow_left_2,
                                color: Colors.white70),
                          ],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: const BoxDecoration(
                          color: AppColors.coral, shape: BoxShape.circle),
                      child: const Icon(IconsaxPlusLinear.close_circle,
                          color: Colors.white, size: 30),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _status == LiveStatus.speaking
                ? IconsaxPlusBold.voice_square
                : IconsaxPlusBold.microphone_2,
            size: 16,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(_statusLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
