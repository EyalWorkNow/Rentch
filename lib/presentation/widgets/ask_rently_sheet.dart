// "שאל את Rently" — a friendly, RTL chat sheet that lets a tenant ask free-text
// Hebrew questions about ONE specific listing ("מותר חיות?", "איזה קומה?",
// "תחבורה ציבורית קרובה?").
//
// It answers INSTANTLY from the listing's own data (floor / rooms / price /
// parking / pets / entry date / nearby transit…) via [answerFromListing] — no
// network needed — and only falls back to the backend for the rest. Anything it
// truly can't answer surfaces a SINGLE CTA to send the question straight to the
// landlord (provider.requestToMessage). Everything is fail-soft: it can never
// break the detail screen.
//
// Designed for older, less tech-savvy users: large tap targets, big readable
// text, suggested-question chips, and plain language.

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

/// Opens the "Ask Rently" Q&A sheet for one [property]. Most questions are
/// answered instantly from the listing's own data; anything it can't answer
/// offers a single CTA to message the landlord directly.
Future<void> showAskRentlySheet(
  BuildContext context, {
  required RentalProperty property,
  String listingTitle = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AskRentlyBody(
      property: property,
      listingTitle: listingTitle,
    ),
  );
}

/// A single line in the conversation.
class _AskMessage {
  _AskMessage({required this.text, required this.fromUser, this.failed = false});
  final String text;
  final bool fromUser;
  final bool failed;
}

class _AskRentlyBody extends StatefulWidget {
  _AskRentlyBody({required this.property, required this.listingTitle});
  final RentalProperty property;
  final String listingTitle;

  @override
  State<_AskRentlyBody> createState() => _AskRentlyBodyState();
}

class _AskRentlyBodyState extends State<_AskRentlyBody> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_AskMessage>[];
  bool _sending = false;
  bool _needsLandlord = false; // a question went unanswered → offer the CTA
  String _lastQuestion = '';
  bool _messaged = false; // guard: send the landlord request once

  List<String> get _suggestions {
    final l10n = AppLocalizations.of(context)!;
    return <String>[
      l10n.askRentlySheet68d09f0e,
      l10n.askRentlySheet8147268b,
      l10n.askRentlySheetE8be946e,
      l10n.askRentlySheet6449ebed,
      l10n.askRentlySheetBd196ab4,
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _ask(String rawQuestion) async {
    final question = rawQuestion.trim();
    if (question.isEmpty || _sending) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _messages.add(_AskMessage(text: question, fromUser: true));
      _sending = true;
      _lastQuestion = question;
      _needsLandlord = false;
      _controller.clear();
    });
    _scrollToEnd();

    // 1) Answer instantly from the listing's own data whenever we can.
    final askL10n = mounted ? AppLocalizations.of(context) : null;
    String? answer = answerFromListing(question, widget.property, l10n: askL10n);

    // 2) Only fall back to the backend for what the data can't cover.
    if (answer == null) {
      try {
        final res = await AwsApiClient.instance.post('/listing/ask', {
          'listingId': widget.property.id,
          'question': question,
        });
        answer = _extractAnswer(res);
      } catch (_) {
        answer = null; // fail-soft: handled below
      }
    }

    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _sending = false;
      if (answer != null && answer.trim().isNotEmpty) {
        _messages.add(_AskMessage(text: answer.trim(), fromUser: false));
      } else {
        // 3) Couldn't answer → offer the single CTA to ask the landlord.
        _messages.add(_AskMessage(
          text: l10n.askRentlySheet47f7f61f,
          fromUser: false,
          failed: true,
        ));
        _needsLandlord = true;
      }
    });
    _scrollToEnd();
  }

  Future<void> _sendToLandlord() async {
    if (_messaged) return;
    _messaged = true;
    final provider = context.read<DatingProvider>();
    final l10n = AppLocalizations.of(context)!;
    final note = _lastQuestion.isNotEmpty ? _lastQuestion : l10n.askRentlySheetD8ba43e9;
    await provider.requestToMessage(widget.property, note: note, l10n: l10n);
    if (!mounted) return;
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2800),
      content: Text(l10n.askRentlySheet700de026),
    ));
  }

  /// Reads the grounded answer from the common backend response shapes.
  static String? _extractAnswer(Map<String, dynamic> res) {
    for (final key in ['answer', 'text', 'message', 'reply']) {
      final v = res[key];
      if (v is String && v.trim().isNotEmpty) return v;
    }
    final data = res['data'];
    if (data is Map) {
      for (final key in ['answer', 'text', 'message', 'reply']) {
        final v = data[key];
        if (v is String && v.trim().isNotEmpty) return v;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Directionality(
      textDirection: Directionality.of(context),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: FractionallySizedBox(
          heightFactor: 0.86,
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                _grabber(),
                _header(context),
                const Divider(height: 1, color: AppColors.divider),
                Expanded(
                  child: _messages.isEmpty ? _emptyState() : _conversation(),
                ),
                if (_sending) _typingIndicator(),
                if (_needsLandlord) _landlordCta(),
                _inputBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Single CTA — appears only when a question couldn't be answered from the data.
  Widget _landlordCta() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: SizedBox(
        height: 52,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: _sendToLandlord,
          icon: const Icon(Icons.send_rounded, size: 20),
          label: Text(l10n.askRentlySheetD92c26c4,
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }

  Widget _grabber() => Container(
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: AppColors.borderLight,
          borderRadius: BorderRadius.circular(999),
        ),
      );

  Widget _header(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(IconsaxPlusLinear.message_question,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.askRentlySheet18b1f617,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  widget.listingTitle.isNotEmpty
                      ? l10n.askRentlySheet6864774c(widget.listingTitle)
                      : l10n.askRentlySheet3ad32172,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.slate500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(IconsaxPlusLinear.close_circle,
                color: AppColors.slate400),
            tooltip: l10n.askRentlySheetB728721f,
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.askRentlySheet108a7146,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.slate600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              for (final s in _suggestions)
                _SuggestionChip(label: s, onTap: () => _ask(s)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _conversation() {
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _messages.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _Bubble(message: _messages[i]),
    );
  }

  Widget _typingIndicator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            AppLocalizations.of(context)!.askRentlySheet804a20ac,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.slate500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.slate100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.send,
                  minLines: 1,
                  maxLines: 4,
                  enabled: !_sending,
                  onSubmitted: _ask,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context)!.askRentlySheet3181ba76,
                    hintStyle: const TextStyle(
                      color: AppColors.slate400,
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _sending ? null : () => _ask(_controller.text),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _sending
                      ? AppColors.primary.withValues(alpha: 0.45)
                      : AppColors.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(IconsaxPlusBold.send_2,
                    color: Colors.white, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grounded, INSTANT answers to common tenant questions from the listing's own
/// fields + the geo index. Returns null only when the data genuinely can't
/// answer — that's when the sheet offers the "message the landlord" CTA.
/// Top-level & pure so it's unit-testable. [l10n] is optional: when supplied
/// (the real app always has a [BuildContext] here) the reply is localized;
/// when omitted (e.g. plain unit tests) it falls back to the Hebrew original.
String? answerFromListing(String q, RentalProperty p, {AppLocalizations? l10n}) {
  final t = q.toLowerCase();
  bool ask(String pat) => RegExp(pat, caseSensitive: false).hasMatch(t);
  final feats = p.features.join(' ').toLowerCase();
  bool has(String pat) => RegExp(pat, caseSensitive: false).hasMatch(feats);
  String rooms() => p.rooms == p.rooms.roundToDouble()
      ? p.rooms.toInt().toString()
      : p.rooms.toString();

  if (ask(r'קומה|באיזו ?קומה|floor')) {
    if (p.floor.trim().isEmpty) return null;
    if (p.totalFloors.trim().isNotEmpty) {
      return l10n != null
          ? l10n.askRentlySheetFloorWithTotal(p.floor, p.totalFloors)
          : 'הדירה בקומה ${p.floor} מתוך ${p.totalFloors}.';
    }
    return l10n != null
        ? l10n.askRentlySheetFloorNoTotal(p.floor)
        : 'הדירה בקומה ${p.floor}.';
  }
  if (ask(r'כמה ?חדר|חדרים|rooms?')) {
    return l10n != null
        ? l10n.askRentlySheetRoomsAnswer(rooms())
        : 'בדירה ${rooms()} חדרים.';
  }
  if (ask(r'גודל|שטח|כמה ?מטר|מ.?ר(?![\wא-ת])|size|sqm|square')) {
    if (p.sizeM2 <= 0) return null;
    return l10n != null
        ? l10n.askRentlySheetSizeAnswer(p.sizeM2)
        : 'שטח הדירה כ-${p.sizeM2} מ״ר.';
  }
  if (ask(r'מחיר|כמה ?עולה|כמה ?זה|שכר ?דירה|שכ.?ד|price|rent|cost')) {
    return l10n != null
        ? l10n.askRentlySheetPriceAnswer(p.price)
        : 'שכר הדירה ${p.price} ₪ לחודש.';
  }
  if (ask(r'חני[יה]|חנה|parking')) {
    final yes = has(r'חני|parking');
    if (l10n != null) {
      return yes
          ? l10n.askRentlySheetParkingYes
          : l10n.askRentlySheetParkingNo;
    }
    return yes
        ? 'כן, יש חניה לדירה.'
        : 'לא צוינה חניה בפרטי הדירה — כדאי לוודא מול בעל הנכס.';
  }
  if (ask(r'חי[הות]|כלב|חתול|מחמד|pet|dog|cat')) {
    final yes = has(r'חיות|pets?|petsallowed|כלב');
    if (l10n != null) {
      return yes ? l10n.askRentlySheetPetsYes : l10n.askRentlySheetPetsNo;
    }
    return yes
        ? 'כן, מותר להחזיק חיות מחמד.'
        : 'לא צוין שמותר להחזיק חיות — עדיף לשאול את בעל הנכס ישירות.';
  }
  if (ask(r'מעלית|elevator|lift')) {
    final yes = has(r'מעלית|elevator|lift');
    if (l10n != null) {
      return yes
          ? l10n.askRentlySheetElevatorYes
          : l10n.askRentlySheetElevatorNo;
    }
    return yes ? 'כן, יש מעלית בבניין.' : 'לא צוינה מעלית בפרטי הדירה.';
  }
  if (ask(r'מרפסת|balcony')) {
    final yes = has(r'מרפסת|balcony');
    if (l10n != null) {
      return yes
          ? l10n.askRentlySheetBalconyYes
          : l10n.askRentlySheetBalconyNo;
    }
    return yes ? 'כן, יש מרפסת.' : 'לא צוינה מרפסת בפרטי הדירה.';
  }
  if (ask(r'ממ.?ד|מקלט|shelter|safe ?room')) {
    final yes = has(r'ממ.?ד|mamad|shelter');
    if (l10n != null) {
      return yes ? l10n.askRentlySheetMamadYes : l10n.askRentlySheetMamadNo;
    }
    return yes ? 'כן, יש ממ״ד.' : 'לא צוין ממ״ד בפרטי הדירה.';
  }
  if (ask(r'מיזוג|מזגן|air ?con|\bac\b')) {
    final yes = has(r'מיזוג|מזגן|\bac\b|air');
    if (l10n != null) {
      return yes ? l10n.askRentlySheetAcYes : l10n.askRentlySheetAcNo;
    }
    return yes ? 'כן, יש מיזוג אוויר.' : 'לא צוין מיזוג בפרטי הדירה.';
  }
  if (ask(r'מרוהט|ריהוט|furnish')) {
    final yes = has(r'מרוהט|ריהוט|furnish');
    if (l10n != null) {
      return yes
          ? l10n.askRentlySheetFurnishedYes
          : l10n.askRentlySheetFurnishedNo;
    }
    return yes ? 'כן, הדירה מרוהטת.' : 'לא צוין ריהוט בפרטי הדירה.';
  }
  if (ask(r'כניסה|מתי ?אפשר|פנוי|מתי ?נכנס|entry|available|move ?in')) {
    if (p.entryDate.trim().isEmpty) {
      return l10n != null
          ? l10n.askRentlySheetEntryUnknown
          : 'לא צוין תאריך כניסה — כדאי לתאם עם בעל הנכס.';
    }
    return l10n != null
        ? l10n.askRentlySheetEntryAnswer(p.entryDate)
        : 'תאריך הכניסה: ${p.entryDate}.';
  }
  if (ask(r'תחבורה|רכבת|אוטובוס|תחנה|רק.?ל|מטרו|transit|train|bus|metro')) {
    final st = IsraelGeoIndex.transitStopsWithin(p.lat, p.lon, km: 2);
    if (st.isEmpty) {
      return l10n != null
          ? l10n.askRentlySheetTransitNone
          : 'לא נמצאה תחנת רכבת/רק״ל במרחק הליכה (עד 2 ק״מ).';
    }
    final d = st.first.km;
    final String dist;
    if (l10n != null) {
      dist = d < 1
          ? l10n.askRentlySheetDistMeters((d * 1000).round())
          : l10n.askRentlySheetDistKm(d.toStringAsFixed(1));
    } else {
      dist = d < 1 ? '${(d * 1000).round()} מ׳' : '${d.toStringAsFixed(1)} ק״מ';
    }
    return l10n != null
        ? l10n.askRentlySheetTransitFound(st.first.name, dist)
        : 'התחנה הקרובה: ${st.first.name} — כ-$dist מהדירה.';
  }
  if (ask(r'שכונה|איפה|כתובת|מיקום|באיזה ?אזור|neighborhood|where|address|location')) {
    final loc = [p.street, p.neighborhood, p.city]
        .where((x) => x.trim().isNotEmpty)
        .join(', ');
    if (loc.isEmpty) return null;
    return l10n != null
        ? l10n.askRentlySheetLocationAnswer(loc)
        : 'הדירה נמצאת ב$loc.';
  }
  return null;
}

class _SuggestionChip extends StatelessWidget {
  _SuggestionChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryDark,
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  _Bubble({required this.message});
  final _AskMessage message;

  @override
  Widget build(BuildContext context) {
    final fromUser = message.fromUser;
    final bg = fromUser
        ? AppColors.primary
        : (message.failed ? AppColors.cloud : AppColors.slate100);
    final fg = fromUser
        ? Colors.white
        : (message.failed ? AppColors.dangerDeep : AppColors.ink);

    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(fromUser ? 18 : 4),
              bottomRight: Radius.circular(fromUser ? 4 : 18),
            ),
          ),
          child: Text(
            message.text,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }
}
