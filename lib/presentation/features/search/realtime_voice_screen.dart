import 'dart:async';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/search/smart_search.dart' show ScoredProperty;
import 'package:dating_app/core/services/realtime_voice_service.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:dating_app/presentation/widgets/liquid_glass_orb.dart';
import 'package:dating_app/presentation/widgets/ati_voice_property_card.dart';
import 'package:flutter/material.dart';

/// Live streaming voice with אתי over the OpenAI Realtime API (GA) — natural
/// streaming speech + native barge-in (talk to interrupt her). Falls back to the
/// turn-based [AtiVoiceScreen] when a live session can't be established.
///
/// [service] is an already-started [RealtimeVoiceService]. [onSearch] runs the
/// real catalogue search for a `search_listings` tool-call and returns a short
/// spoken summary + the result cards to show inline.
class RealtimeVoiceScreen extends StatefulWidget {
  const RealtimeVoiceScreen({
    super.key,
    required this.service,
    required this.onSearch,
  });

  final RealtimeVoiceService service;
  final Future<({List<ScoredProperty> results, String summary})> Function(
      Map<String, dynamic> args) onSearch;

  @override
  State<RealtimeVoiceScreen> createState() => _RealtimeVoiceScreenState();
}

class _RealtimeVoiceScreenState extends State<RealtimeVoiceScreen> {
  RealtimeState _state = RealtimeState.connecting;
  String _userLine = '';
  // Falls back to a localized greeting (see build()) until the real transcript
  // starts streaming in — kept empty here since l10n needs a BuildContext.
  String _atiLine = '';
  List<ScoredProperty> _results = const [];
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.add(widget.service.state.listen((s) {
      if (mounted) setState(() => _state = s);
    }));
    _subs.add(widget.service.userTranscript.listen((t) {
      if (mounted) setState(() => _userLine = t);
    }));
    _subs.add(widget.service.assistantTranscript.listen((d) {
      if (mounted) {
        setState(() => _atiLine =
            (_state == RealtimeState.speaking ? _atiLine : '') + d);
      }
    }));
    _subs.add(widget.service.toolCall.listen((call) async {
      final r = await widget.onSearch(call.args);
      if (!mounted) return;
      setState(() => _results = r.results);
      widget.service.sendToolResult(call.callId, r.summary);
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  double get _activity {
    switch (_state) {
      case RealtimeState.listening:
        return 0.55;
      case RealtimeState.speaking:
        return 0.85;
      case RealtimeState.thinking:
        return 0.45;
      case RealtimeState.connecting:
      case RealtimeState.idle:
      case RealtimeState.error:
        return 0.2;
    }
  }

  String _status(AppLocalizations l10n) {
    switch (_state) {
      case RealtimeState.connecting:
        return l10n.realtimeVoiceScreenA7587542;
      case RealtimeState.listening:
        return l10n.realtimeVoiceScreen85084af4;
      case RealtimeState.thinking:
        return l10n.realtimeVoiceScreenA6de1c7e;
      case RealtimeState.speaking:
        return l10n.realtimeVoiceScreen0658343f;
      case RealtimeState.idle:
        return l10n.realtimeVoiceScreen9aea3a09;
      case RealtimeState.error:
        return l10n.realtimeVoiceScreenE60120ca;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                Row(children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.white70, size: 32),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  Column(children: [
                    Text(l10n.realtimeVoiceScreen8e4d1523,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    Text(l10n.realtimeVoiceScreen5a17ea8a,
                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ]),
                  const Spacer(),
                  const SizedBox(width: 48),
                ]),
                const Spacer(),
                Text(_status(l10n),
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 26),
                LiquidGlassOrb(
                    size: 175,
                    level: _activity,
                    speaking: _state == RealtimeState.speaking),
                const SizedBox(height: 30),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Text(
                    _state == RealtimeState.listening && _userLine.isNotEmpty
                        ? _userLine
                        : (_atiLine.isEmpty
                            ? l10n.realtimeVoiceScreenE3b9c24d
                            : _atiLine),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 19, height: 1.5),
                  ),
                ),
                const Spacer(),
                if (_results.isNotEmpty) _resultsStrip(l10n),
                // Safety net: if the live session misbehaves, drop to the reliable
                // turn-based (tap-to-talk) screen.
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l10n.realtimeVoiceScreenAf4fd15c,
                      style: const TextStyle(color: Colors.white54, fontSize: 13)),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16, top: 4),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: const BoxDecoration(
                          color: AppColors.coral, shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded,
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

  // Same map/discover ("לאסו") card design + detailed "why", scrollable.
  Widget _resultsStrip(AppLocalizations l10n) {
    return Flexible(
      flex: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(l10n.realtimeVoiceScreen38f0b537(_results.length),
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ),
          Flexible(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _results.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AtiVoicePropertyCard(
                  scored: _results[i],
                  width: double.infinity,
                  height: 380,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          PropertyDetailScreen(property: _results[i].property))),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
