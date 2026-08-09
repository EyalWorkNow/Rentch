import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/assistant_live_service.dart' show LiveStatus;
import 'package:dating_app/core/services/openai_realtime_service.dart';
import 'package:dating_app/core/services/property_draft_builder.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/widgets/liquid_glass_orb.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

/// Full-screen LIVE (speech-to-speech) conversation with עזרא over the OpenAI
/// Realtime API. עזרא listens, collects the essentials, and when he has them he
/// calls create_property — which this screen publishes to the landlord's
/// listings (photos are added afterwards in "הדירות שלי").
///
/// Mirrors [AtiLiveVoiceScreen]; on connect failure it pops and calls
/// [onConnectFailed] so the caller can fall back to the turn-based עזרא.
class ErikLiveVoiceScreen extends StatefulWidget {
  const ErikLiveVoiceScreen({super.key, this.onConnectFailed});

  final VoidCallback? onConnectFailed;

  @override
  State<ErikLiveVoiceScreen> createState() => _ErikLiveVoiceScreenState();
}

class _ErikLiveVoiceScreenState extends State<ErikLiveVoiceScreen> {
  final OpenAiRealtimeService _live = OpenAiRealtimeService(mode: 'landlord');
  LiveStatus _status = LiveStatus.connecting;
  String _userText = '';
  String _erikText = ''; // empty until the first real chunk arrives
  bool _published = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _live
      ..onStatus = (s) {
        if (mounted) setState(() => _status = s);
      }
      ..onUserText = (t) {
        if (mounted) setState(() => _userText = t.trim());
      }
      ..onErikText = (t) {
        if (mounted) {
          setState(() {
            _erikText = _status == LiveStatus.speaking && _erikText.isNotEmpty
                ? '$_erikText$t'
                : t;
          });
        }
      }
      ..onTurnComplete = () {
        if (mounted) setState(() => _userText = '');
      }
      ..onCreateProperty = (args) async {
        final provider = context.read<DatingProvider>();
        final ownerName = provider.tenantProfile?.name ?? '';
        try {
          final property = await buildPropertyFromErikDraft(
            args,
            ownerName: ownerName,
            photoUrls: const <String>[],
          );
          await provider.addLandlordProperty(property);
          if (mounted) setState(() => _published = true);
        } catch (_) {/* עזרא still confirms by voice; user can retry */}
      }
      ..onSearchListings = ((args) async {
        return mounted
            ? AppLocalizations.of(context)!.erikLiveVoiceScreen4ec210b3
            : '';
      })
      ..onError = (msg) {
        if (_failed) return;
        _failed = true;
        if (mounted) {
          Navigator.of(context).maybePop();
          widget.onConnectFailed?.call();
        }
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
        return l10n.erikLiveVoiceScreenD5fa2760;
      case LiveStatus.listening:
        return l10n.erikLiveVoiceScreen15ec4d84;
      case LiveStatus.speaking:
        return l10n.erikLiveVoiceScreenC4ad4681;
      case LiveStatus.error:
        return l10n.erikLiveVoiceScreenAa5a9e29;
      case LiveStatus.idle:
      case LiveStatus.closed:
        return l10n.erikLiveVoiceScreenC21710c8;
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
    final erikDisplay =
        _erikText.isNotEmpty ? _erikText : l10n.erikLiveVoiceScreenD5fa2760;
    final caption = _userText.isNotEmpty ? _userText : erikDisplay;
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
                if (_published)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        children: [
                          Icon(IconsaxPlusBold.tick_circle,
                              color: AppColors.success, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                                AppLocalizations.of(context)!
                                    .erikLiveVoiceScreen01302f08,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
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
