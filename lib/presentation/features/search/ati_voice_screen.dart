import 'dart:async';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/services/assistant_service.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:dating_app/presentation/widgets/liquid_glass_orb.dart';
import 'package:dating_app/presentation/widgets/speed_mode_slider.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/ati_voice_property_card.dart';
import 'package:flutter/material.dart';

/// Full-screen voice conversation with אתי — styled after Google Gemini's live
/// voice UI (fluid multi-colour morphing blob, live captions, minimal controls),
/// with Rently touches: אתי persona, understood-criteria chips, a results peek.
///
/// Runs on the device STT (he-IL) → אתי (GPT) → device TTS turn-based loop. The
/// [demoMode] flag renders a live-looking still (no mic) for previews/screenshots.
enum AtiVoiceState { idle, listening, thinking, speaking }

/// What one spoken turn produces. [needLocation] asks the voice screen to pop an
/// animated "share my location" button instead of grabbing GPS silently.
class VoiceTurn {
  const VoiceTurn({
    required this.reply,
    this.showResults = false,
    this.results = const [],
    this.needLocation = false,
  });
  final String reply;
  final bool showResults;
  final List<ScoredProperty> results;
  final bool needLocation;
}

class AtiVoiceScreen extends StatefulWidget {
  const AtiVoiceScreen({
    super.key,
    required this.service,
    required this.onUtterance,
    this.onShareLocation,
    this.onNewConversation,
    this.criteria = const [],
    this.resultCount = 0,
    this.demoMode = false,
  });

  final AssistantService service;
  final Future<VoiceTurn> Function(String transcript) onUtterance;

  /// Called when the user taps the "share my location" button — capture GPS and
  /// run the held search, returning the resulting turn.
  final Future<VoiceTurn> Function()? onShareLocation;

  /// Called when the user starts a fresh conversation (clears the held query).
  final VoidCallback? onNewConversation;

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
  late List<String> _criteria = List.of(widget.criteria);
  late int _resultCount = widget.resultCount;
  List<ScoredProperty> _results = const []; // options shown inline in this screen
  final PageController _carousel = PageController(viewportFraction: 0.88);
  int _page = 0;
  bool _recording = false; // holding the orb to record
  bool _sending = false; // guards against a double-send on release
  bool _needLocation = false; // show the animated "share my location" button
  bool _locating = false; // guards the share-location tap (independent of _sending)

  @override
  void initState() {
    super.initState();
    if (widget.demoMode) {
      _transcript = 'אני מחפשת 3 חדרים בתל אביב, קרוב לים, עם מרפסת…';
      _criteria = const ['תל אביב', '3 חדרים', 'עד 8,000 ₪', 'מרפסת', 'ליד הים'];
      _resultCount = 7;
      _level = 0.6;
    }
    // Push-to-talk: nothing starts on its own — the user HOLDS the orb to record.
  }

  // Press-and-HOLD the orb → record with the `record` plugin (NO native
  // recogniser → no beeps, no flicker, never stuck). Release → Whisper transcribes
  // → onUtterance → אתי answers. The user fully controls start/stop.
  Future<void> _startRecording() async {
    if (widget.demoMode || _recording || _sending) return;
    if (_state == AtiVoiceState.speaking) {
      await widget.service.stopSpeaking(); // barge-in
    }
    if (!mounted) return;
    setState(() {
      _recording = true;
      _state = AtiVoiceState.listening;
      _transcript = '';
      _level = 0;
    });
    final ok = await widget.service.startRecording(onLevel: (l) {
      if (mounted) setState(() => _level = _level * 0.5 + l * 0.5);
    });
    if (!ok && mounted) {
      final err = widget.service.lastRecordError;
      setState(() {
        _recording = false;
        _state = AtiVoiceState.idle;
        _reply = err == 'permission'
            ? 'צריך הרשאת מיקרופון — אשרו בהגדרות המכשיר 🎙️'
            : 'לא הצלחתי להתחיל הקלטה 🙈\n${err ?? ''}';
      });
    }
  }

  Future<void> _stopAndSend() async {
    if (!_recording || _sending) return;
    _recording = false;
    _sending = true;
    if (mounted) {
      setState(() {
        _state = AtiVoiceState.thinking;
        _level = 0;
      });
    }
    try {
      final text = await widget.service.stopRecordingAndTranscribe();
      if (!mounted) return;
      if (text.trim().isEmpty) {
        final err = widget.service.lastRecordError;
        setState(() {
          _state = AtiVoiceState.idle;
          _reply = 'לא שמעתי אותך 🙈 החזק/י את הכדור ודבר/י'
              '${err != null ? '\n($err)' : ''}';
        });
        return;
      }
      setState(() => _transcript = text);
      await _respond(text);
    } finally {
      _sending = false;
    }
  }

  Future<void> _respond(String text) async {
    try {
      final result = await widget.onUtterance(text).timeout(
        const Duration(seconds: 25),
        onTimeout: () => const VoiceTurn(
            reply: 'סליחה, לקח לי רגע יותר מדי 🙈 אפשר לנסות שוב?'),
      );
      await _applyTurn(result);
    } catch (_) {
      // network / model error → keep the screen usable
      if (mounted) setState(() => _state = AtiVoiceState.idle);
    }
  }

  // Renders a turn: reply text, results carousel, TTS, and — when the assistant
  // needs the user's whereabouts — the animated "share my location" button.
  Future<void> _applyTurn(VoiceTurn result) async {
    if (!mounted) return;
    setState(() {
      _reply = result.reply;
      _needLocation = result.needLocation && widget.onShareLocation != null;
      _state = AtiVoiceState.speaking;
      if (result.results.isNotEmpty) {
        _results = result.results;
        _resultCount = result.results.length;
        _page = 0;
      }
    });
    if (result.results.isNotEmpty && _carousel.hasClients) {
      _carousel.jumpToPage(0);
    }
    try {
      await widget.service.speak(result.reply);
    } catch (_) {}
    if (mounted) setState(() => _state = AtiVoiceState.idle);
  }

  // User tapped "share my location" → capture GPS + run the held search. NB: this
  // must NOT be gated by _sending — that flag stays true while אתי is still SPEAKING
  // the "share location?" prompt, which used to make the button do nothing.
  Future<void> _shareLocation() async {
    final cb = widget.onShareLocation;
    if (cb == null || _locating) return;
    _locating = true;
    await widget.service.stopSpeaking(); // barge-in over her prompt
    if (mounted) {
      setState(() {
        _needLocation = false;
        _state = AtiVoiceState.thinking;
      });
    }
    try {
      await _applyTurn(await cb());
    } catch (_) {
      if (mounted) setState(() => _state = AtiVoiceState.idle);
    } finally {
      _locating = false;
    }
  }

  // The animated "share my location" button — springs in when אתי needs to know
  // where the user is (voice "דירה באזור שלי").
  Widget _locationButton() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.elasticOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) =>
          ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
      child: !_needLocation
          ? const SizedBox.shrink(key: ValueKey('no-loc'))
          : Padding(
              key: const ValueKey('loc-btn'),
              padding: const EdgeInsets.only(top: 20),
              child: _PulseLocationCta(onTap: _shareLocation),
            ),
    );
  }

  @override
  void dispose() {
    _carousel.dispose();
    if (!widget.demoMode) {
      widget.service.cancelRecording();
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


  // ── copy ───────────────────────────────────────────────────────────────────
  String get _statusLabel {
    switch (_state) {
      case AtiVoiceState.listening:
        return 'מקשיבה… שחרר/י כדי לשלוח';
      case AtiVoiceState.thinking:
        return 'רגע, חושבת…';
      case AtiVoiceState.speaking:
        return 'אתי מדברת · החזק/י כדי לענות';
      case AtiVoiceState.idle:
        return 'החזק/י את הכדור כדי לדבר 🎙️';
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
                // Speed mode — fast (on-device) ↔ personalization (AI). Shared
                // live with the text chat.
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: SpeedMode.immediate,
                    builder: (_, immediate, __) => SpeedModeSlider(
                      immediate: immediate,
                      onChanged: SpeedMode.set,
                    ),
                  ),
                ),
                if (_criteria.isNotEmpty) _criteriaChips(),
                const Spacer(),
                _statusPill(),
                const SizedBox(height: 12),
                _blob(),
                const SizedBox(height: 30),
                _captionText(caption),
                _locationButton(),
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
            icon: const Icon(IconsaxPlusLinear.arrow_down_1,
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
          IconButton(
            tooltip: 'שיחה חדשה',
            icon: const Icon(IconsaxPlusLinear.edit_2,
                color: Colors.white70, size: 28),
            onPressed: _newConversation,
          ),
        ],
      ),
    );
  }

  // Start over — clears the held query (via the callback) and the on-screen state.
  void _newConversation() {
    widget.onNewConversation?.call();
    if (!mounted) return;
    setState(() {
      _reply = 'שיחה חדשה 👋 מה נחפש עכשיו?';
      _transcript = '';
      _results = const [];
      _resultCount = 0;
      _criteria = [];
      _needLocation = false;
      _state = AtiVoiceState.idle;
    });
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
    // Shrink the orb once results are on screen so the carousel gets real room.
    final size = _results.isEmpty ? 175.0 : 104.0;
    // Press-and-HOLD to record, release to send. Listener fires on the raw
    // pointer down/up so the hold can last any length (unlike a tap/long-press).
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _startRecording(),
      onPointerUp: (_) => _stopAndSend(),
      onPointerCancel: (_) => _stopAndSend(),
      child: LiquidGlassOrb(
        size: size,
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
  // Inside the voice conversation, apartments use the SAME map/discover ("לאסו")
  // card design, with the detailed "why", in a scrollable vertical list.
  // A horizontal, swipeable CAROUSEL of the suggested apartments — each card
  // gets real room and can scroll internally if its "why" is expanded.
  Widget _resultsStrip() {
    return Flexible(
      flex: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('מצאתי ${_results.length} דירות שמתאימות לך 👇',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: PageView.builder(
              controller: _carousel,
              onPageChanged: (i) => setState(() => _page = i),
              itemCount: _results.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: AtiVoicePropertyCard(
                  scored: _results[i],
                  width: double.infinity,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          PropertyDetailScreen(property: _results[i].property))),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _carouselDots(),
        ],
      ),
    );
  }

  Widget _carouselDots() {
    final n = _results.length.clamp(0, 12);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < n; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _page ? 20 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == _page
                  ? AppColors.primary
                  : Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
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
              Icon(IconsaxPlusBold.home_2, color: AppColors.primary, size: 22),
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
              const Icon(IconsaxPlusLinear.arrow_left_2, color: Colors.white70),
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
          Listener(
            onPointerDown: (_) => _startRecording(),
            onPointerUp: (_) => _stopAndSend(),
            onPointerCancel: (_) => _stopAndSend(),
            child: _roundBtn(
              icon: _recording ? IconsaxPlusBold.microphone : IconsaxPlusLinear.microphone,
              bg: _recording
                  ? const Color(0xFF7CE0E6).withValues(alpha: 0.30)
                  : Colors.white.withValues(alpha: 0.12),
              onTap: () {},
            ),
          ),
          _roundBtn(
            icon: _state == AtiVoiceState.speaking
                ? IconsaxPlusLinear.voice_square
                : IconsaxPlusLinear.keyboard,
            bg: Colors.white.withValues(alpha: 0.12),
            onTap: () => Navigator.of(context).maybePop(),
          ),
          _roundBtn(
            icon: IconsaxPlusLinear.close_circle,
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

// A location-pin CTA with a continuous soft pulse, so it clearly invites a tap
// when אתי needs to know where the user is ("דירה באזור שלי").
class _PulseLocationCta extends StatefulWidget {
  const _PulseLocationCta({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_PulseLocationCta> createState() => _PulseLocationCtaState();
}

class _PulseLocationCtaState extends State<_PulseLocationCta>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF7CE0E6);
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = _c.value;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.5 * (1 - t)),
                  blurRadius: 8 + 26 * t,
                  spreadRadius: 1 + 6 * t,
                ),
              ],
            ),
            child: child,
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF17C7D1), Color(0xFF6675FF)]),
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(IconsaxPlusLinear.gps, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('שיתוף המיקום שלי',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}
