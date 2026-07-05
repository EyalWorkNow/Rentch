import 'dart:async';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/search/smart_search.dart' show ScoredProperty;
import 'package:dating_app/core/services/realtime_voice_service.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:dating_app/presentation/widgets/liquid_glass_orb.dart';
import 'package:dating_app/presentation/widgets/assistant_property_card.dart';
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
  String _atiLine = 'שלום, אני אתי 👋 פשוט דברו איתי.';
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

  String get _status {
    switch (_state) {
      case RealtimeState.connecting:
        return 'מתחברת…';
      case RealtimeState.listening:
        return 'מקשיבה לך…';
      case RealtimeState.thinking:
        return 'רגע, חושבת…';
      case RealtimeState.speaking:
        return 'אתי מדברת · פשוט דברו כדי להפריע';
      case RealtimeState.idle:
        return 'דברו איתי';
      case RealtimeState.error:
        return 'הייתה תקלה בחיבור';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.35),
              radius: 1.25,
              colors: [Color(0xFF0E2A44), Color(0xFF071726), Color(0xFF03080E)],
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
                  const Column(children: [
                    Text('אתי',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    Text('שיחה חיה • Rently',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ]),
                  const Spacer(),
                  const SizedBox(width: 48),
                ]),
                const Spacer(),
                Text(_status,
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
                        : _atiLine,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 19, height: 1.5),
                  ),
                ),
                const Spacer(),
                if (_results.isNotEmpty) _resultsStrip(),
                // Safety net: if the live session misbehaves, drop to the reliable
                // turn-based (tap-to-talk) screen.
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('עבור לשיחה רגילה 💬',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16, top: 4),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: const BoxDecoration(
                          color: Color(0xFFFF5A67), shape: BoxShape.circle),
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
  Widget _resultsStrip() {
    return Flexible(
      flex: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text('מצאתי ${_results.length} דירות שמתאימות לך 👇',
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
                child: AssistantPropertyCard(
                  scored: _results[i],
                  width: double.infinity,
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
