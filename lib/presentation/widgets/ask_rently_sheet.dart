// "שאל את Rently" — a friendly, RTL chat sheet that lets a tenant ask free-text
// Hebrew questions about ONE specific listing ("מותר חיות?", "איזה קומה?",
// "תחבורה ציבורית קרובה?") and get a grounded Hebrew answer from the backend.
//
// It calls the generic AWS client:
//   AwsApiClient.instance.post('/listing/ask', {'listingId': ..., 'question': ...})
// and reads the answer defensively from a few common shapes
// ({answer} / {data:{answer}} / {text} / {message}). Everything is fail-soft:
// a network error or empty body shows a calm Hebrew "couldn't answer" line
// instead of throwing, so the sheet can never break the detail screen.
//
// Designed for older, less tech-savvy users: large tap targets, big readable
// text, suggested-question chips, and plain language.

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// Opens the "Ask Rently" Q&A sheet for the listing identified by [listingId].
/// [listingTitle] is shown in the header for context (optional, plain string).
Future<void> showAskRentlySheet(
  BuildContext context, {
  required String listingId,
  String listingTitle = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AskRentlyBody(
      listingId: listingId,
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
  const _AskRentlyBody({required this.listingId, required this.listingTitle});
  final String listingId;
  final String listingTitle;

  @override
  State<_AskRentlyBody> createState() => _AskRentlyBodyState();
}

class _AskRentlyBodyState extends State<_AskRentlyBody> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_AskMessage>[];
  bool _sending = false;

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
      _controller.clear();
    });
    _scrollToEnd();

    String? answer;
    try {
      final res = await AwsApiClient.instance.post('/listing/ask', {
        'listingId': widget.listingId,
        'question': question,
      });
      answer = _extractAnswer(res);
    } catch (_) {
      answer = null; // fail-soft: handled below
    }

    if (!mounted) return;
    setState(() {
      _sending = false;
      if (answer != null && answer.trim().isNotEmpty) {
        _messages.add(_AskMessage(text: answer.trim(), fromUser: false));
      } else {
        _messages.add(_AskMessage(
          text: 'לא הצלחנו לענות על זה כרגע. אפשר לנסות שוב, '
              'או לשאול את בעל הנכס ישירות.',
          fromUser: false,
          failed: true,
        ));
      }
    });
    _scrollToEnd();
  }

  /// Reads the grounded answer from the common response shapes the backend
  /// might use, without assuming any one of them is present.
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
                const Divider(height: 1, color: Color(0xFFE8F0F5)),
                Expanded(
                  child: _messages.isEmpty ? _emptyState() : _conversation(),
                ),
                if (_sending) _typingIndicator(),
                _inputBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _grabber() => Container(
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: const Color(0xFFD8E8F0),
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
                    color: Color(0xFF0F172A),
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
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(IconsaxPlusLinear.close_circle,
                color: Color(0xFF94A3B8)),
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
              color: Color(0xFF475569),
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
              color: Color(0xFF64748B),
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
                  color: const Color(0xFFF1F5F9),
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
                    color: Color(0xFF0F172A),
                  ),
                  decoration: const InputDecoration(
                    hintText: 'כתבו שאלה על הדירה…',
                    hintStyle: TextStyle(
                      color: Color(0xFF94A3B8),
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
          border:
              Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
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
        : (message.failed ? const Color(0xFFFFF1F2) : const Color(0xFFF1F5F9));
    final fg = fromUser
        ? Colors.white
        : (message.failed ? const Color(0xFFB91C1C) : const Color(0xFF0F172A));

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
