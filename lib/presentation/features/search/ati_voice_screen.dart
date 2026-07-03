import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/services/assistant_service.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:dating_app/presentation/widgets/liquid_glass_orb.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';

/// Full-screen voice conversation with אתי — styled after Google Gemini's live
/// voice UI (fluid multi-colour morphing blob, live captions, minimal controls),
/// with Rently touches: אתי persona, understood-criteria chips, a results peek.
///
/// Runs on the device STT (he-IL) → אתי (GPT) → device TTS turn-based loop. The
/// [demoMode] flag renders a live-looking still (no mic) for previews/screenshots.
enum AtiVoiceState { idle, listening, thinking, speaking }

class AtiVoiceScreen extends StatefulWidget {
  const AtiVoiceScreen({
    super.key,
    required this.service,
    required this.onUtterance,
    this.criteria = const [],
    this.resultCount = 0,
    this.demoMode = false,
  });

  final AssistantService service;
  final Future<({String reply, bool showResults, List<ScoredProperty> results})>
      Function(String transcript) onUtterance;

  /// Understood search criteria to show as glassy chips (city / rooms / budget…).
  final List<String> criteria;

  /// How many real listings אתי has surfaced so far (drives the results peek).
  final int resultCount;

  /// Preview/screenshot mode: paints a lifelike "listening" state without a mic.
  final bool demoMode;

  @override
  State<AtiVoiceScreen> createState() => _AtiVoiceScreenState();
}

class _AtiVoiceScreenState extends State<AtiVoiceScreen> {
  late AtiVoiceState _state = widget.demoMode
      ? AtiVoiceState.listening
      : AtiVoiceState.idle;
  String _transcript = '';
  String _reply = 'שלום, אני אתי 👋\nספרו לי מה אתם מחפשים.';
  double _level = 0; // smoothed mic level 0..1
  bool _muted = false;
  late List<String> _criteria = List.of(widget.criteria);
  late int _resultCount = widget.resultCount;
  List<ScoredProperty> _results = const []; // options shown inline in this screen

  @override
  void initState() {
    super.initState();
    if (widget.demoMode) {
      _transcript = 'אני מחפשת 3 חדרים בתל אביב, קרוב לים, עם מרפסת…';
      _criteria = const ['תל אביב', '3 חדרים', 'עד 8,000 ₪', 'מרפסת', 'ליד הים'];
      _resultCount = 7;
      _level = 0.6;
    }
  }

  @override
  void dispose() {
    if (!widget.demoMode) {
      widget.service.stopListening();
      widget.service.stopSpeaking();
    }
    super.dispose();
  }

  // Overall "aliveness" for the balls: brightest while speaking, mic-driven while
  // listening, calm at rest.
  double get _activity {
    switch (_state) {
      case AtiVoiceState.listening:
        return 0.25 + _level * 0.75;
      case AtiVoiceState.speaking:
        return 0.85;
      case AtiVoiceState.thinking:
        return 0.45;
      case AtiVoiceState.idle:
        return 0.18;
    }
  }

  // ── voice loop ─────────────────────────────────────────────────────────────
  Future<void> _toggleListen() async {
    if (widget.demoMode) return;
    if (_state == AtiVoiceState.listening) {
      await widget.service.stopListening();
      setState(() => _state = AtiVoiceState.idle);
      return;
    }
    if (_state == AtiVoiceState.thinking || _state == AtiVoiceState.speaking) {
      return;
    }
    await _startListening();
  }

  Future<void> _startListening() async {
    setState(() {
      _state = AtiVoiceState.listening;
      _transcript = '';
    });
    try {
      await widget.service.startListening(
        onResult: (text, isFinal) {
          if (!mounted) return;
          setState(() => _transcript = text);
          if (isFinal) _handle(text);
        },
        onSoundLevelChange: (lvl) {
          if (!mounted) return;
          final n = ((lvl + 2) / 12).clamp(0.0, 1.0);
          setState(() => _level = _level * 0.6 + n * 0.4);
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = AtiVoiceState.idle;
        _reply = 'לא הצלחתי להפעיל את המיקרופון. בדקו שאישרתם הרשאה.';
      });
    }
  }

  Future<void> _handle(String text) async {
    await widget.service.stopListening();
    if (text.trim().isEmpty) {
      if (mounted) setState(() => _state = AtiVoiceState.idle);
      return;
    }
    setState(() {
      _state = AtiVoiceState.thinking;
      _level = 0;
    });
    final result = await widget.onUtterance(text);
    if (!mounted) return;
    setState(() {
      _reply = result.reply;
      _state = AtiVoiceState.speaking;
      // Show the options INSIDE the voice screen (no auto-close).
      if (result.results.isNotEmpty) _results = result.results;
      if (result.results.isNotEmpty) _resultCount = result.results.length;
    });
    try {
      await widget.service.speak(result.reply);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _state = AtiVoiceState.idle);
  }

  // ── copy ───────────────────────────────────────────────────────────────────
  String get _statusLabel {
    switch (_state) {
      case AtiVoiceState.listening:
        return 'מקשיבה לך…';
      case AtiVoiceState.thinking:
        return 'רגע, חושבת…';
      case AtiVoiceState.speaking:
        return 'אתי מדברת';
      case AtiVoiceState.idle:
        return 'הקישו כדי לדבר';
    }
  }

  @override
  Widget build(BuildContext context) {
    final caption = (_state == AtiVoiceState.listening && _transcript.isNotEmpty)
        ? _transcript
        : _reply;
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
                _topBar(),
                if (_criteria.isNotEmpty) _criteriaChips(),
                const Spacer(),
                _statusPill(),
                const SizedBox(height: 26),
                _blob(),
                const SizedBox(height: 30),
                _captionText(caption),
                const Spacer(),
                if (_results.isNotEmpty)
                  _resultsStrip()
                else if (_resultCount > 0)
                  _resultsPeek(),
                _controls(),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.white70, size: 32),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const Spacer(),
          Column(
            children: const [
              Text('אתי',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3)),
              Text('שיחה קולית • Rently',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _criteriaChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in _criteria)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Text(c,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _statusPill() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Text(
        _statusLabel,
        key: ValueKey(_statusLabel),
        style: TextStyle(
          color: AppColors.primary,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _blob() {
    return GestureDetector(
      onTap: _toggleListen,
      child: LiquidGlassOrb(
        size: 175,
        level: widget.demoMode ? 0.6 : _activity,
        speaking: widget.demoMode || _state == AtiVoiceState.speaking,
      ),
    );
  }

  Widget _captionText(String caption) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Text(
          caption,
          key: ValueKey(caption),
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontSize: 19, height: 1.5, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  // The property options אתי found — shown as a horizontal strip of glassy cards
  // right inside the voice screen (tap → full details).
  Widget _resultsStrip() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('מצאתי ${_results.length} דירות שמתאימות לך 👇',
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            height: 176,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _results.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _miniCard(_results[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniCard(ScoredProperty s) {
    final p = s.property;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PropertyDetailScreen(property: p))),
      child: Container(
        width: 156,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 100,
              child: SafeMedia(
                media: p.primaryMedia,
                fallback: Container(
                  color: Colors.white.withValues(alpha: 0.06),
                  child: const Icon(Icons.home_rounded,
                      color: Colors.white24, size: 32),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.priceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('${p.roomsLabel} · ${p.city}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultsPeek() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.home_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text('מצאתי $_resultCount דירות שמתאימות לך',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
              const Text('הצג',
                  style: TextStyle(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              const Icon(Icons.chevron_left_rounded, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _roundBtn(
            icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            bg: Colors.white.withValues(alpha: 0.12),
            onTap: () => setState(() => _muted = !_muted),
          ),
          _roundBtn(
            icon: _state == AtiVoiceState.speaking
                ? Icons.graphic_eq_rounded
                : Icons.keyboard_rounded,
            bg: Colors.white.withValues(alpha: 0.12),
            onTap: () => Navigator.of(context).maybePop(),
          ),
          _roundBtn(
            icon: Icons.close_rounded,
            bg: const Color(0xFFFF5A67),
            onTap: () => Navigator.of(context).maybePop(),
            big: true,
          ),
        ],
      ),
    );
  }

  Widget _roundBtn({
    required IconData icon,
    required Color bg,
    required VoidCallback onTap,
    bool big = false,
  }) {
    final size = big ? 68.0 : 58.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: big ? 30 : 26),
      ),
    );
  }
}
