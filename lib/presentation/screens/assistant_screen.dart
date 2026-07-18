import 'dart:async';
import 'package:dating_app/core/ui/platform_fx.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/assistant_service.dart';
import 'package:dating_app/core/services/property_draft_builder.dart';
import 'package:dating_app/core/services/storage_service.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/features/assistant/erik_design.dart';
import 'package:dating_app/presentation/features/assistant/erik_presence.dart';
import 'package:dating_app/presentation/features/assistant/erik_voice_call.dart';
import 'package:dating_app/presentation/screens/add_property_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Erik design tokens ────────────────────────────────────────────────────────
// The full token layer lives in `features/assistant/erik_design.dart`
// (ErikTokens). These short aliases keep this screen's call-sites concise; they
// are a thin re-export so there is still a SINGLE source of truth. The accent is
// NEVER hard-coded — it flows from AppColors (auto BLACK for brokers, teal
// otherwise). Never `const` a widget that reads an accent token.
const _kBgDeep = ErikTokens.bgDeep; // deepest navy (top & bottom of canvas)
const _kBgMid = ErikTokens.bgMid; // lifted navy (centre glow)
const _kInk = ErikTokens.ink; // primary text on dark
const _kMuted = ErikTokens.muted; // muted blue-grey (secondary text)
const _kLine = ErikTokens.line; // hairline border for glassmorphism
const _kLineStrong = ErikTokens.lineStrong; // brighter hairline
Color get _kUserSurface => ErikTokens.userSurface; // solid accent (user bubble)
Color get _kAccent => ErikTokens.accent; // teal / black per role
Color get _kAccent2 => ErikTokens.accentGlow; // luminous accent for glow

/// "אריק" — a premium, VOICE-FIRST concierge for landlords, rebuilt around a
/// single glowing orb (Siri / ChatGPT-voice style). One big living orb in the
/// centre is the whole interface: tap it to start talking; a short status line
/// and live waveform sit under it; Erik's latest reply appears as minimal text;
/// a small control row offers mic, a keyboard fallback, and end. Built so both a
/// 20-year-old and a 70-year-old breeze through it.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen>
    with TickerProviderStateMixin {
  final _service = AssistantService();
  final _inputCtrl = TextEditingController();
  final _picker = ImagePicker();
  final _storage = StorageService();

  final List<AssistantTurn> _turns = [];
  final List<String> _photoUrls = [];
  bool _pickingPhoto = false;
  Map<String, dynamic>? _draft;
  bool _thinking = false;
  bool _listening = false;
  bool _voiceReplies = true;
  bool _publishing = false;
  String _partial = '';

  // Whether the text composer (keyboard fallback) is revealed.
  bool _showComposer = false;

  // Hands-free voice conversation: when on, Erik listens automatically, the user
  // speaks, Erik answers in his natural voice and immediately resumes listening —
  // like a phone call, with no buttons. Built for older landlords. This is the
  // voice experience (true streaming Live isn't available for this key).
  bool _conversationMode = false;

  late final AnimationController _pulse;
  late final AnimationController _composerCtrl;
  late final Animation<Offset> _composerOffset;
  late final AnimationController _uploadPanelCtrl;
  late final Animation<Offset> _uploadPanelOffset;

  static const _greeting =
      'שלום, נעים מאוד. קוראים לי אריק ואני כאן כדי לעזור לך.\n'
      'ספר לי בבקשה בכמה מילים על הדירה שאתה רוצה להשכיר — איפה היא, כמה חדרים, '
      'וכל מה שבא לך לספר. מתוך מה שתספר אני כבר אבין הרבה, ואשאל רק על מה שחסר.\n'
      'אפשר לדבר איתי או לכתוב, איך שנוח לך.';

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'guest';
  String get _storeKey => 'erik_transcript_$_uid';

  final ValueNotifier<double> _soundLevelNotifier = ValueNotifier<double>(0.0);

  /// Maps the screen's many flags into the four expressive presence states that
  /// drive Erik's orb. One place, so the orb and status line stay in sync.
  ErikState get _erikState {
    if (_thinking) return ErikState.thinking;
    if (_listening) return ErikState.listening;
    return ErikState.idle;
  }

  /// True whenever a voice conversation is going (hands-free or mic on).
  bool get _callActive => _conversationMode || _listening;

  /// The short status line under the orb, derived from the real state.
  String get _statusLine {
    if (_thinking) return 'חושב...';
    if (_listening) return 'מקשיב לך...';
    if (_conversationMode) return 'מקשיב לך...';
    return 'שלום, אני אריק';
  }

  /// Erik's latest reply text (minimal) — the last committed assistant turn.
  String get _erikReply {
    final last = _turns.lastWhere(
      (t) => t.role == 'assistant',
      orElse: () => const AssistantTurn(role: 'assistant', text: ''),
    );
    final text = last.text.trim();
    // Don't surface the long greeting as the "latest reply" — the orb hint
    // covers the idle invitation instead.
    if (text == _greeting) return '';
    return text;
  }

  /// The user's last utterance (current STT partial > last turn).
  String get _userLine {
    if (_listening && _partial.trim().isNotEmpty) return _partial.trim();
    final last = _turns.lastWhere(
      (t) => t.role == 'user',
      orElse: () => const AssistantTurn(role: 'user', text: ''),
    );
    return last.text.trim();
  }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);

    _composerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _composerOffset = Tween<Offset>(
      begin: const Offset(0.0, 1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _composerCtrl,
      curve: Curves.easeOutCubic,
    ));

    _uploadPanelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _uploadPanelOffset = Tween<Offset>(
      begin: const Offset(0.0, 1.2), // completely below screen
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _uploadPanelCtrl,
      curve: Curves.easeOutBack,
    ));

    _service.ttsVoice = 'onyx'; // אריק — a natural male voice (אתי stays 'coral')
    _loadTranscript();

    // Hands-free by default: the voice conversation starts on its own so the
    // landlord can just talk — no tap to start, no tap per turn (Erik listens,
    // answers, and resumes listening automatically).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_conversationMode) _toggleConversation();
    });
  }

  @override
  void dispose() {
    _conversationMode = false;
    _pulse.dispose();
    _composerCtrl.dispose();
    _uploadPanelCtrl.dispose();
    _service.dispose();
    _inputCtrl.dispose();
    _soundLevelNotifier.dispose();
    super.dispose();
  }

  // ── Persistence ──────────────────────────────────────────────────────────────

  AssistantTurn _welcomeTurn() => const AssistantTurn(
        role: 'assistant',
        text: _greeting,
      );

  Future<void> _loadTranscript() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storeKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _turns.addAll(list.whereType<Map>().map(
              (e) => AssistantTurn.fromJson(Map<String, dynamic>.from(e)),
            ));
      }
    } catch (_) {}
    if (_turns.isEmpty) {
      _turns.add(_welcomeTurn());
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveTranscript() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storeKey,
        jsonEncode(_turns.map((t) => t.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _clearTranscript() async {
    await _service.stopSpeaking();
    setState(() {
      _turns
        ..clear()
        ..add(_welcomeTurn());
      _draft = null;
      _photoUrls.clear();
    });
    _saveTranscript();
  }

  // ── Conversation ──────────────────────────────────────────────────────────────

  Future<void> _send(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || _thinking) return;
    _inputCtrl.clear();
    setState(() {
      _turns.add(AssistantTurn(role: 'user', text: clean));
      _thinking = true;
      _partial = '';
      // NOTE: do NOT clear _draft here. A draft Erik already built must stay
      // publishable across the rest of the conversation (the user keeps talking,
      // especially in hands-free voice mode) until it is actually published.
    });
    _saveTranscript();

    try {
      final history = _turns.where((t) => t.text != _greeting).toList();
      final reply = await _service.chat(history);
      if (!mounted) return;
      final hadDraft = _draft != null;
      setState(() {
        _turns.add(AssistantTurn(
          role: 'assistant',
          text: reply.reply,
          // Carry the search_listings tool results so the thread can paint them.
          cards: reply.cards,
        ));
        // Only replace the pending draft when Erik produced a new one; keep the
        // previous draft otherwise so its publish action never disappears.
        if (reply.propertyDraft != null) _draft = reply.propertyDraft;
        _thinking = false;
      });
      _saveTranscript();
      if (_asksForPhotos(reply.reply)) {
        _openUploadPanel();
      }
      // When Erik just built a fresh draft, surface a minimal publish sheet.
      if (reply.propertyDraft != null && !hadDraft) {
        _showDraftSheet(reply.propertyDraft!);
      }
      if (_conversationMode) {
        await _speakAndContinue(reply.reply);
      } else if (_voiceReplies) {
        _service.speak(reply.reply);
      }
    } on AssistantException catch (e) {
      _onError(e.message);
    } catch (_) {
      _onError('משהו השתבש. אפשר לנסות שוב.');
    }
  }

  /// Speaks Erik's reply and, while in hands-free conversation mode, resumes
  /// listening as soon as he finishes — so the user just keeps talking.
  Future<void> _speakAndContinue(String text) async {
    if (_voiceReplies) {
      await _service.speak(text);
    }
    if (_conversationMode && mounted && !_thinking && !_publishing) {
      _listenTurn();
    }
  }

  void _onError(String message) {
    if (!mounted) return;
    setState(() {
      _turns.add(AssistantTurn(role: 'assistant', text: message));
      _thinking = false;
    });
    // Keep the hands-free call alive: speak the message and listen again.
    if (_conversationMode) {
      unawaited(_speakAndContinue(message));
    }
  }

  // ── Text composer (keyboard fallback) ─────────────────────────────────────────

  void _openComposer() {
    setState(() => _showComposer = true);
    _composerCtrl.forward();
  }

  void _closeComposer() {
    FocusScope.of(context).unfocus();
    _composerCtrl.reverse().then((_) {
      if (mounted) setState(() => _showComposer = false);
    });
  }

  void _sendFromComposer(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    _send(clean);
    _closeComposer();
  }

  // ── Media ──────────────────────────────────────────────────────────────────

  void _openUploadPanel() {
    _uploadPanelCtrl.forward();
  }

  void _closeUploadPanel() {
    _uploadPanelCtrl.reverse();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_pickingPhoto) return;
    setState(() => _pickingPhoto = true);
    try {
      final file = await _picker.pickImage(
          source: source, imageQuality: 88, maxWidth: 2000);
      if (file == null) {
        if (mounted) setState(() => _pickingPhoto = false);
        return;
      }
      final localPath =
          await _storage.saveImageLocally(file, folderName: 'erik_property');
      final remoteUrl = await _storage.uploadToCloud(localPath);
      if (!mounted) return;
      final mediaPath = remoteUrl ?? localPath;
      final wasFirstPhoto = _photoUrls.isEmpty;
      setState(() {
        _photoUrls.add(mediaPath);
        _turns.add(AssistantTurn(
          role: 'user',
          text: 'הוספתי תמונה לדירה',
          mediaUrls: [mediaPath],
        ));
        _pickingPhoto = false;
      });
      _saveTranscript();
      _maybeResumePublish(wasFirstPhoto);
    } catch (_) {
      if (!mounted) return;
      setState(() => _pickingPhoto = false);
      _onError('לא הצלחתי להוסיף את התמונה. אפשר לנסות שוב.');
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    if (_pickingPhoto) return;
    setState(() => _pickingPhoto = true);
    try {
      final file = await _picker.pickVideo(
          source: source, maxDuration: const Duration(seconds: 30));
      if (file == null) {
        if (mounted) setState(() => _pickingPhoto = false);
        return;
      }
      final localPath =
          await _storage.saveImageLocally(file, folderName: 'erik_property');
      final remoteUrl = await _storage.uploadToCloud(localPath);
      if (!mounted) return;
      final mediaPath = remoteUrl ?? localPath;
      final wasFirstMedia = _photoUrls.isEmpty;
      setState(() {
        _photoUrls.add(mediaPath);
        _turns.add(AssistantTurn(
          role: 'user',
          text: 'הוספתי סרטון לדירה',
          mediaUrls: [mediaPath],
        ));
        _pickingPhoto = false;
      });
      _saveTranscript();
      _maybeResumePublish(wasFirstMedia);
    } catch (_) {
      if (!mounted) return;
      setState(() => _pickingPhoto = false);
      _onError('לא הצלחתי להוסיף את הסרטון. אפשר לנסות שוב.');
    }
  }

  /// When Erik already built a draft and the user just added their FIRST photo
  /// (the only thing that was blocking publishing), close the upload panel and
  /// re-surface the publish sheet so the listing actually goes live — the photo
  /// requirement is now satisfied.
  void _maybeResumePublish(bool wasFirstMedia) {
    if (!wasFirstMedia || _draft == null || _publishing) return;
    _closeUploadPanel();
    _showDraftSheet(_draft!);
  }

  Future<void> _publishDraft([Map<String, dynamic>? draftOverride]) async {
    final draft = draftOverride ?? _draft;
    if (draft == null || _publishing) return;
    if (_photoUrls.isEmpty) {
      setState(() {
        _turns.add(const AssistantTurn(
          role: 'assistant',
          text:
              'רק רגע — כדי לפרסם צריך לפחות תמונה אחת של הדירה. אפשר לצלם עכשיו או לבחור תמונה מהטלפון.',
        ));
      });
      _openUploadPanel();
      return;
    }
    setState(() => _publishing = true);
    try {
      final provider = context.read<DatingProvider>();
      final ownerName = provider.tenantProfile?.name ?? '';
      final property = await buildPropertyFromErikDraft(
        draft,
        ownerName: ownerName,
        photoUrls: _photoUrls,
      );
      await provider.addLandlordProperty(property);
      if (!mounted) return;
      final addr = [
        property.street,
        property.streetNumber > 0 ? '${property.streetNumber}' : '',
        property.city,
      ].where((e) => e.isNotEmpty).join(' ');
      final msg =
          'מצוין! פרסמתי את הדירה שלך${addr.isNotEmpty ? ' ב$addr' : ''}, היא כבר באוויר.\n'
          'אם תרצה, אפשר להוסיף עוד תמונות בכל רגע מהמסך "הדירות שלי".\n'
          'אני כאן אם תצטרך עוד משהו.';
      setState(() {
        _draft = null;
        _publishing = false;
        _photoUrls.clear();
        _turns.add(AssistantTurn(role: 'assistant', text: msg));
      });
      _saveTranscript();
      if (_voiceReplies) _service.speak(msg);
    } catch (e, st) {
      if (kDebugMode) debugPrint('Erik publishDraft failed: $e\n$st');
      if (!mounted) return;
      setState(() => _publishing = false);
      _onError(
          'סליחה, הייתה בעיה בפרסום. אפשר לנסות שוב, או להוסיף תמונות ידנית.');
    }
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _service.stopListening();
      setState(() => _listening = false);
      _soundLevelNotifier.value = 0.0;
      if (_partial.trim().isNotEmpty) _send(_partial);
      return;
    }
    await _service.stopSpeaking();
    try {
      setState(() {
        _listening = true;
        _partial = '';
      });
      await _service.startListening(
        onResult: (text, isFinal) {
          setState(() => _partial = text);
          if (isFinal) {
            setState(() => _listening = false);
            _soundLevelNotifier.value = 0.0;
            if (text.trim().isNotEmpty) _send(text);
          }
        },
        onSoundLevelChange: (level) {
          _soundLevelNotifier.value = level;
        },
      );
    } on AssistantException catch (e) {
      setState(() => _listening = false);
      _soundLevelNotifier.value = 0.0;
      _onError(e.message);
    }
  }

  // ── Hands-free voice conversation (turn-based, feels like a phone call) ───────

  /// Tapping the orb starts/stops a hands-free VOICE CONVERSATION: Erik listens,
  /// the user talks, Erik answers in his natural voice and immediately resumes
  /// listening — no buttons. True real-time streaming Live isn't available for
  /// this key, so this snappy turn-based loop is the voice experience.
  Future<void> _toggleConversation() async {
    if (_conversationMode) {
      setState(() => _conversationMode = false);
      await _service.stopSpeaking();
      await _service.stopListening();
      if (mounted) {
        setState(() {
          _listening = false;
        });
        _soundLevelNotifier.value = 0.0;
      }
      return;
    }
    setState(() {
      _conversationMode = true;
      _voiceReplies = true; // a voice conversation is, by definition, spoken
    });
    await _service.stopSpeaking();
    if (!mounted || !_conversationMode) return;
    _listenTurn();
  }

  /// One listening turn within conversation mode. On a final result it sends the
  /// text (which then speaks + loops back here). If nothing was heard, it keeps
  /// listening so a quiet pause never ends the call.
  Future<void> _listenTurn() async {
    if (!_conversationMode || !mounted || _thinking) return;
    await _service.stopSpeaking();
    if (!_conversationMode || !mounted) return;
    try {
      setState(() {
        _listening = true;
        _partial = '';
      });
      await _service.startListening(
        onResult: (text, isFinal) {
          if (!mounted) return;
          setState(() => _partial = text);
          if (isFinal) {
            setState(() => _listening = false);
            _soundLevelNotifier.value = 0.0;
            final clean = text.trim();
            if (clean.isNotEmpty) {
              _send(clean);
            } else if (_conversationMode) {
              _listenTurn();
            }
          }
        },
        onSoundLevelChange: (level) {
          _soundLevelNotifier.value = level;
        },
      );
    } on AssistantException catch (e) {
      // Mic unavailable / permission denied — end the call cleanly.
      setState(() {
        _listening = false;
        _conversationMode = false;
      });
      _soundLevelNotifier.value = 0.0;
      _onError(e.message);
    }
  }

  bool _asksForPhotos(String text) {
    final clean = text.toLowerCase();
    return clean.contains('תמונה') ||
        clean.contains('תמונות') ||
        clean.contains('לצלם') ||
        clean.contains('סרטון') ||
        clean.contains('סירטון') ||
        clean.contains('גלריה');
  }

  // ── End / close ──────────────────────────────────────────────────────────────

  Future<void> _close() async {
    await _service.stopSpeaking();
    await _service.stopListening();
    _conversationMode = false;
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _toggleVoice() async {
    if (_voiceReplies) await _service.stopSpeaking();
    setState(() => _voiceReplies = !_voiceReplies);
  }

  // ── UI ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgDeep,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // ── The calm "night" canvas: a deep navy radial that lifts toward the
          // centre, so the orb feels lit from within the screen. ──
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.15),
                  radius: 1.25,
                  colors: [_kBgMid, _kBgDeep],
                  stops: [0.0, 1.0],
                ),
              ),
            ),
          ),
          // Soft, brand-driven ambient aurora — on-theme (auto black for brokers,
          // teal for tenants), gently animated so the screen breathes.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final t = _pulse.value;
                  return Stack(
                    children: [
                      Positioned(
                        top: -150 + 14 * t,
                        right: -120,
                        child: _ambientGlow(
                            360, _kAccent2.withValues(alpha: 0.14 + 0.05 * t)),
                      ),
                      Positioned(
                        bottom: -160,
                        left: -130 + 14 * (1 - t),
                        child: _ambientGlow(
                            400, _kAccent.withValues(alpha: 0.13 + 0.04 * t)),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // ── Top bar: back + kebab options (minimal, floats over the canvas) ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(
                  children: [
                    _glassCircleBtn(
                        IconsaxPlusLinear.arrow_right_3, _close),
                    const Spacer(),
                    _glassCircleBtn(
                      IconsaxPlusLinear.more,
                      _showOptionsMenu,
                      color: _kInk.withValues(alpha: 0.72),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── The orb stage — the whole interface ─────────────────────────────
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              return ErikOrbStage(
                clock: _pulse.value,
                state: _erikState,
                connecting: false,
                callActive: _callActive,
                statusLine: _statusLine,
                erikReply: _erikReply,
                userLine: _userLine,
                soundLevel: _soundLevelNotifier,
                voiceOn: _voiceReplies,
                onTapOrb: _toggleConversation,
                onToggleMic: _toggleMic,
                onOpenKeyboard: _openComposer,
                onToggleVoice: _toggleVoice,
                onClose: _close,
              );
            },
          ),

          // ── Text composer (keyboard fallback) ───────────────────────────────
          if (_showComposer)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SlideTransition(
                position: _composerOffset,
                child: ErikTextComposer(
                  controller: _inputCtrl,
                  onSend: _sendFromComposer,
                  onClose: _closeComposer,
                  onAddMedia: _openUploadPanel,
                ),
              ),
            ),

          // ── Media upload panel (photos / video) ─────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SlideTransition(
              position: _uploadPanelOffset,
              child: _buildUploadPanel(),
            ),
          ),
        ],
      ),
    );
  }

  /// A soft circular brand glow used in the ambient background.
  Widget _ambientGlow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, Colors.transparent],
        ),
      ),
    );
  }

  Widget _glassCircleBtn(IconData icon, VoidCallback onTap, {Color? color}) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            shape: BoxShape.circle,
            border: Border.all(color: _kLine),
          ),
          child: Icon(icon, color: color ?? _kInk, size: 22),
        ),
      ),
    );
  }

  // ── Minimal draft sheet (uses the existing publish flow) ──────────────────────

  /// When Erik builds a property draft in the typed/hands-free flow, surface it
  /// as a minimal card sheet with a publish button wired to [_publishDraft].
  void _showDraftSheet(Map<String, dynamic> draft) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => _DraftSheet(
          draft: draft,
          photoCount: _photoUrls.length,
          publishing: _publishing,
          onPublish: () {
            Navigator.pop(ctx);
            _publishDraft(draft);
          },
          onEdit: () {
            Navigator.pop(ctx);
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AddPropertyScreen(initialDraft: draft),
            ));
          },
          onAddPhotos: () {
            Navigator.pop(ctx);
            _openUploadPanel();
          },
        ),
      );
    });
  }

  Widget _buildUploadPanel() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(22), sigmaY: PlatformFx.blurSigma(22)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          decoration: BoxDecoration(
            color: _kBgMid.withValues(alpha: 0.94),
            border: const Border(top: BorderSide(color: _kLineStrong)),
          ),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.82,
              ),
              child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: _kMuted.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'הוספת מדיה לדירה',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    GestureDetector(
                      onTap: _closeUploadPanel,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(IconsaxPlusLinear.close_circle,
                            color: Colors.white70, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (_photoUrls.isEmpty)
                  Container(
                    height: 80,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _kLine),
                    ),
                    child: const Text(
                      'טרם הוספת תמונות לדירה זו',
                      style: TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                  )
                else
                  SizedBox(
                    height: 80,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _photoUrls.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _thumb(_photoUrls[i]),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _photoUrls.removeAt(i);
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  IconsaxPlusLinear.close_circle,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _panelActionBtn(
                        icon: IconsaxPlusBold.camera,
                        label: 'צלם תמונה',
                        color: _kAccent,
                        onTap: () => _pickPhoto(ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _panelActionBtn(
                        icon: IconsaxPlusBold.gallery,
                        label: 'גלריה',
                        color: AppColors.superLike,
                        onTap: () => _pickPhoto(ImageSource.gallery),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _panelActionBtn(
                        icon: IconsaxPlusBold.video_play,
                        label: 'צלם וידאו',
                        color: AppColors.coral,
                        onTap: () => _pickVideo(ImageSource.camera),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _kUserSurface,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _closeUploadPanel,
                  child: const Text(
                    'סיימתי, המשך בשיחה',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panelActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(String url) {
    const fallback = SizedBox(
      width: 72,
      height: 72,
      child: ColoredBox(
        color: Color(0x1F5AD4DC),
        child: Icon(IconsaxPlusLinear.gallery, color: _kMuted),
      ),
    );
    if (url.startsWith('http')) {
      return Image.network(url,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback);
    }
    return Image.file(File(url),
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback);
  }

  void _showOptionsMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(20), sigmaY: PlatformFx.blurSigma(20)),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
            decoration: BoxDecoration(
              color: AppColors.navy.withValues(alpha: 0.94),
              border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: _kMuted.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  if (_draft != null) ...[
                    _OptionTile(
                      icon: IconsaxPlusBold.house_2,
                      label: 'פרסם את טיוטת הדירה',
                      subtitle: 'אריק כבר בנה טיוטה — אפשר לפרסם',
                      onTap: () {
                        Navigator.pop(ctx);
                        _showDraftSheet(_draft!);
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  _OptionTile(
                    icon: IconsaxPlusBold.gallery_add,
                    label: 'הוסף תמונות',
                    subtitle: 'צלם או בחר תמונות לדירה',
                    onTap: () {
                      Navigator.pop(ctx);
                      _openUploadPanel();
                    },
                  ),
                  const SizedBox(height: 8),
                  _OptionTile(
                    icon: _voiceReplies
                        ? IconsaxPlusLinear.volume_slash
                        : IconsaxPlusBold.volume_high,
                    label: _voiceReplies ? 'השתק קול' : 'הפעל קול',
                    subtitle: _voiceReplies
                        ? 'אריק לא ידבר בקול'
                        : 'אריק ידבר את תשובותיו בקול',
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (_voiceReplies) await _service.stopSpeaking();
                      setState(() => _voiceReplies = !_voiceReplies);
                    },
                  ),
                  const SizedBox(height: 8),
                  _OptionTile(
                    icon: IconsaxPlusLinear.refresh,
                    label: 'שיחה חדשה',
                    subtitle: 'מחק היסטוריה והתחל מחדש',
                    onTap: () {
                      Navigator.pop(ctx);
                      _clearTranscript();
                    },
                    destructive: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Minimal draft sheet ───────────────────────────────────────────────────────

/// A compact card surfacing Erik's property draft, with the real publish flow.
class _DraftSheet extends StatelessWidget {
  const _DraftSheet({
    required this.draft,
    required this.photoCount,
    required this.publishing,
    required this.onPublish,
    required this.onEdit,
    required this.onAddPhotos,
  });

  final Map<String, dynamic> draft;
  final int photoCount;
  final bool publishing;
  final VoidCallback onPublish;
  final VoidCallback onEdit;
  final VoidCallback onAddPhotos;

  @override
  Widget build(BuildContext context) {
    String v(String k) => (draft[k]?.toString() ?? '').trim();
    final addr = [v('street'), v('streetNumber'), v('city')]
        .where((e) => e.isNotEmpty)
        .join(' ');
    final lines = <String>[
      if (addr.isNotEmpty) '📍  $addr',
      if (v('rooms').isNotEmpty) '🚪  ${v('rooms')} חדרים',
      if (v('floor').isNotEmpty) '🏢  קומה ${v('floor')}',
      if (v('price').isNotEmpty) '💰  ${v('price')} ₪ לחודש',
      if (v('sizeM2').isNotEmpty) '📐  ${v('sizeM2')} מ"ר',
      if (v('condition').isNotEmpty) '✨  ${v('condition')}',
      if (v('entryDate').isNotEmpty) '📅  כניסה: ${v('entryDate')}',
    ];
    final hasPhotos = photoCount > 0;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(22), sigmaY: PlatformFx.blurSigma(22)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          decoration: BoxDecoration(
            color: _kBgMid.withValues(alpha: 0.96),
            border: const Border(top: BorderSide(color: _kLineStrong)),
          ),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.82,
              ),
              child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: _kMuted.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text(
                      'טיוטת דירה',
                      style: TextStyle(
                        color: _kInk,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _kAccent.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(IconsaxPlusBold.house_2,
                          color: _kAccent, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...lines.map((l) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.5),
                      child: Text(
                        l,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: _kInk,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    )),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      hasPhotos
                          ? 'נוספו $photoCount תמונות'
                          : 'צריך לפחות תמונה אחת',
                      style: TextStyle(
                          color: hasPhotos ? _kAccent : AppColors.coral,
                          fontSize: 14,
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                        hasPhotos
                            ? IconsaxPlusBold.tick_circle
                            : IconsaxPlusBold.gallery,
                        color: hasPhotos ? _kAccent : AppColors.coral,
                        size: 20),
                  ],
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onAddPhotos,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kAccent,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    side: BorderSide(
                        color: _kAccent.withValues(alpha: 0.35), width: 1.3),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13)),
                  ),
                  icon: const Icon(IconsaxPlusBold.gallery_add, size: 20),
                  label: const Text('הוסף או ערוך תמונות',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: ErikTokens.userSurface,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: publishing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(IconsaxPlusBold.tick_circle, size: 20),
                  label: Text(
                    publishing ? 'מפרסם את הדירה...' : 'כן, פרסם את הדירה',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  onPressed: publishing ? null : onPublish,
                ),
                Center(
                  child: TextButton(
                    onPressed: publishing ? null : onEdit,
                    child: const Text(
                      'פתח עריכה מלאה',
                      style: TextStyle(
                        color: _kMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
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

// ── Option tile used in the kebab options sheet ───────────────────────────────

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.error : _kAccent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.20)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: destructive ? color : _kInk,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: _kMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Icon(IconsaxPlusLinear.arrow_left_2,
                color: _kMuted.withValues(alpha: 0.55), size: 18),
          ],
        ),
      ),
    );
  }
}
