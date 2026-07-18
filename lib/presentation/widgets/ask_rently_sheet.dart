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
  const _AskRentlyBody({required this.property, required this.listingTitle});
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

  static const _suggestions = <String>[
    'מותר להחזיק חיות מחמד?',
    'באיזו קומה הדירה?',
    'יש תחבורה ציבורית קרובה?',
    'יש חניה?',
    'מתי אפשר להיכנס?',
  ];

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
    String? answer = answerFromListing(question, widget.property);

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
    setState(() {
      _sending = false;
      if (answer != null && answer.trim().isNotEmpty) {
        _messages.add(_AskMessage(text: answer.trim(), fromUser: false));
      } else {
        // 3) Couldn't answer → offer the single CTA to ask the landlord.
        _messages.add(_AskMessage(
          text: 'אין לי את המידע הזה על הדירה. אפשר לשלוח את השאלה '
              'ישירות לבעל הנכס:',
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
    final note = _lastQuestion.isNotEmpty ? _lastQuestion : 'שאלה על הדירה';
    await provider.requestToMessage(widget.property, note: note);
    if (!mounted) return;
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      duration: Duration(milliseconds: 2800),
      content: Text('השאלה נשלחה לבעל הנכס — תופיע אצלו תחת '
          '"מבקשים לשלוח הודעה"'),
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
      textDirection: TextDirection.rtl,
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
          label: const Text('שלח את השאלה לבעל הדירה',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
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
                const Text(
                  'שאל את Rently',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  widget.listingTitle.isNotEmpty
                      ? 'שאלות על ${widget.listingTitle}'
                      : 'שאלות על הנכס הזה',
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
            tooltip: 'סגירה',
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'אפשר לשאול אותי כל דבר על הדירה הזו — בעברית פשוטה. הנה כמה דוגמאות:',
            style: TextStyle(
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
          const Text(
            'Rently חושב…',
            style: TextStyle(
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
                  decoration: const InputDecoration(
                    hintText: 'כתבו שאלה על הדירה…',
                    hintStyle: TextStyle(
                      color: AppColors.slate400,
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
/// Top-level & pure so it's unit-testable.
String? answerFromListing(String q, RentalProperty p) {
  final t = q.toLowerCase();
  bool ask(String pat) => RegExp(pat, caseSensitive: false).hasMatch(t);
  final feats = p.features.join(' ').toLowerCase();
  bool has(String pat) => RegExp(pat, caseSensitive: false).hasMatch(feats);
  String rooms() => p.rooms == p.rooms.roundToDouble()
      ? p.rooms.toInt().toString()
      : p.rooms.toString();

  if (ask(r'קומה|באיזו ?קומה|floor')) {
    if (p.floor.trim().isEmpty) return null;
    final of = p.totalFloors.trim().isNotEmpty ? ' מתוך ${p.totalFloors}' : '';
    return 'הדירה בקומה ${p.floor}$of.';
  }
  if (ask(r'כמה ?חדר|חדרים|rooms?')) return 'בדירה ${rooms()} חדרים.';
  if (ask(r'גודל|שטח|כמה ?מטר|מ.?ר(?![\wא-ת])|size|sqm|square')) {
    return p.sizeM2 > 0 ? 'שטח הדירה כ-${p.sizeM2} מ״ר.' : null;
  }
  if (ask(r'מחיר|כמה ?עולה|כמה ?זה|שכר ?דירה|שכ.?ד|price|rent|cost')) {
    return 'שכר הדירה ${p.price} ₪ לחודש.';
  }
  if (ask(r'חני[יה]|חנה|parking')) {
    return has(r'חני|parking')
        ? 'כן, יש חניה לדירה.'
        : 'לא צוינה חניה בפרטי הדירה — כדאי לוודא מול בעל הנכס.';
  }
  if (ask(r'חי[הות]|כלב|חתול|מחמד|pet|dog|cat')) {
    return has(r'חיות|pets?|petsallowed|כלב')
        ? 'כן, מותר להחזיק חיות מחמד.'
        : 'לא צוין שמותר להחזיק חיות — עדיף לשאול את בעל הנכס ישירות.';
  }
  if (ask(r'מעלית|elevator|lift')) {
    return has(r'מעלית|elevator|lift')
        ? 'כן, יש מעלית בבניין.'
        : 'לא צוינה מעלית בפרטי הדירה.';
  }
  if (ask(r'מרפסת|balcony')) {
    return has(r'מרפסת|balcony') ? 'כן, יש מרפסת.' : 'לא צוינה מרפסת בפרטי הדירה.';
  }
  if (ask(r'ממ.?ד|מקלט|shelter|safe ?room')) {
    return has(r'ממ.?ד|mamad|shelter') ? 'כן, יש ממ״ד.' : 'לא צוין ממ״ד בפרטי הדירה.';
  }
  if (ask(r'מיזוג|מזגן|air ?con|\bac\b')) {
    return has(r'מיזוג|מזגן|\bac\b|air')
        ? 'כן, יש מיזוג אוויר.'
        : 'לא צוין מיזוג בפרטי הדירה.';
  }
  if (ask(r'מרוהט|ריהוט|furnish')) {
    return has(r'מרוהט|ריהוט|furnish')
        ? 'כן, הדירה מרוהטת.'
        : 'לא צוין ריהוט בפרטי הדירה.';
  }
  if (ask(r'כניסה|מתי ?אפשר|פנוי|מתי ?נכנס|entry|available|move ?in')) {
    return p.entryDate.trim().isNotEmpty
        ? 'תאריך הכניסה: ${p.entryDate}.'
        : 'לא צוין תאריך כניסה — כדאי לתאם עם בעל הנכס.';
  }
  if (ask(r'תחבורה|רכבת|אוטובוס|תחנה|רק.?ל|מטרו|transit|train|bus|metro')) {
    final st = IsraelGeoIndex.transitStopsWithin(p.lat, p.lon, km: 2);
    if (st.isEmpty) return 'לא נמצאה תחנת רכבת/רק״ל במרחק הליכה (עד 2 ק״מ).';
    final d = st.first.km;
    final dist = d < 1 ? '${(d * 1000).round()} מ׳' : '${d.toStringAsFixed(1)} ק״מ';
    return 'התחנה הקרובה: ${st.first.name} — כ-$dist מהדירה.';
  }
  if (ask(r'שכונה|איפה|כתובת|מיקום|באיזה ?אזור|neighborhood|where|address|location')) {
    final loc = [p.street, p.neighborhood, p.city]
        .where((x) => x.trim().isNotEmpty)
        .join(', ');
    return loc.isNotEmpty ? 'הדירה נמצאת ב$loc.' : null;
  }
  return null;
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});
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
  const _Bubble({required this.message});
  final _AskMessage message;

  @override
  Widget build(BuildContext context) {
    final fromUser = message.fromUser;
    final bg = fromUser
        ? AppColors.primary
        : (message.failed ? AppColors.cloud : AppColors.slate100);
    final fg = fromUser
        ? Colors.white
        : (message.failed ? const Color(0xFFB91C1C) : AppColors.ink);

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
