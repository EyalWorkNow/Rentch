import 'dart:convert';

/// In-chat "propose viewing times" payloads.
///
/// [ChatMessage] is intentionally plain-text-only (`{id, sender, text, ...}`),
/// so structured scheduling data is encoded *inside* the message text behind a
/// machine marker — exactly the spirit of the existing contract cards, which
/// trigger rich UI from chat state without changing the message model.
///
/// Wire format (marker always at the END of the text, after a human line):
///   proposal → `<hebrew line>\n[[SLOTS:<json>]]`
///   confirm  → `<hebrew line>\n[[SLOT_CONFIRM:<json>]]`
///
/// Anything that doesn't carry a well-formed marker is treated as [SlotPlain]
/// so ordinary messages render exactly as before.

/// One proposed viewing window.
class SlotOption {
  const SlotOption({
    required this.slotId,
    required this.start,
    required this.durationMinutes,
  });

  final String slotId;
  final DateTime start;
  final int durationMinutes;

  Map<String, dynamic> toJson() => {
        'slotId': slotId,
        'start': start.toIso8601String(),
        'durationMinutes': durationMinutes,
      };

  factory SlotOption.fromJson(Map<String, dynamic> json) => SlotOption(
        slotId: json['slotId']?.toString() ?? '',
        start: DateTime.parse(json['start'].toString()),
        durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 30,
      );
}

/// A landlord's proposal: a property + up to a few [SlotOption]s to pick from.
class SlotProposal {
  const SlotProposal({required this.propertyId, required this.options});

  final String propertyId;
  final List<SlotOption> options;

  Map<String, dynamic> toJson() => {
        'propertyId': propertyId,
        'options': options.map((o) => o.toJson()).toList(),
      };

  factory SlotProposal.fromJson(Map<String, dynamic> json) => SlotProposal(
        propertyId: json['propertyId']?.toString() ?? '',
        options: (json['options'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => SlotOption.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// A tenant's confirmation of one specific proposed slot.
class SlotConfirm {
  const SlotConfirm({
    required this.slotId,
    required this.start,
    required this.durationMinutes,
    required this.propertyId,
  });

  final String slotId;
  final DateTime start;
  final int durationMinutes;
  final String propertyId;

  Map<String, dynamic> toJson() => {
        'slotId': slotId,
        'start': start.toIso8601String(),
        'durationMinutes': durationMinutes,
        'propertyId': propertyId,
      };

  factory SlotConfirm.fromJson(Map<String, dynamic> json) => SlotConfirm(
        slotId: json['slotId']?.toString() ?? '',
        start: DateTime.parse(json['start'].toString()),
        durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 30,
        propertyId: json['propertyId']?.toString() ?? '',
      );
}

/// Typed result of [SlotMessageCodec.parse].
sealed class SlotParseResult {
  const SlotParseResult();
}

class SlotProposalMessage extends SlotParseResult {
  const SlotProposalMessage(this.proposal);
  final SlotProposal proposal;
}

class SlotConfirmMessage extends SlotParseResult {
  const SlotConfirmMessage(this.confirm);
  final SlotConfirm confirm;
}

/// A normal, non-scheduling message (or one with a malformed marker).
class SlotPlainMessage extends SlotParseResult {
  const SlotPlainMessage();
}

class SlotMessageCodec {
  SlotMessageCodec._();

  static const String _proposalOpen = '[[SLOTS:';
  static const String _confirmOpen = '[[SLOT_CONFIRM:';
  static const String _close = ']]';

  // ── Encode ─────────────────────────────────────────────────────────────────

  static String encodeProposal(SlotProposal proposal) {
    final n = proposal.options.length;
    final human = n == 1
        ? 'הצעתי מועד לצפייה בדירה 🗓️'
        : 'הצעתי $n מועדים לצפייה בדירה 🗓️';
    return '$human\n$_proposalOpen${jsonEncode(proposal.toJson())}$_close';
  }

  static String encodeConfirm(SlotConfirm confirm) {
    const human = 'אישרתי מועד לצפייה בדירה ✓';
    return '$human\n$_confirmOpen${jsonEncode(confirm.toJson())}$_close';
  }

  // ── Parse ──────────────────────────────────────────────────────────────────

  static SlotParseResult parse(String text) {
    final proposalJson = _payload(text, _proposalOpen);
    if (proposalJson != null) {
      try {
        final decoded = jsonDecode(proposalJson);
        if (decoded is Map) {
          final proposal =
              SlotProposal.fromJson(Map<String, dynamic>.from(decoded));
          if (proposal.options.isNotEmpty) {
            return SlotProposalMessage(proposal);
          }
        }
      } catch (_) {
        // Malformed → fall through to plain.
      }
    }

    final confirmJson = _payload(text, _confirmOpen);
    if (confirmJson != null) {
      try {
        final decoded = jsonDecode(confirmJson);
        if (decoded is Map) {
          return SlotConfirmMessage(
              SlotConfirm.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (_) {
        // Malformed → fall through to plain.
      }
    }

    return const SlotPlainMessage();
  }

  /// The text to show when falling back to plain rendering: the human line with
  /// any `[[...]]` marker stripped out. Robust to a marker with no closing `]]`.
  static String displayText(String text) {
    for (final open in const [_proposalOpen, _confirmOpen]) {
      final i = text.indexOf(open);
      if (i < 0) continue;
      final end = text.indexOf(_close, i + open.length);
      if (end < 0) continue; // malformed → leave text untouched
      final before = text.substring(0, i);
      final after = text.substring(end + _close.length);
      return '$before$after'.trim();
    }
    return text.trim();
  }

  /// Returns the JSON payload between [open] and the next `]]`, or null if the
  /// marker is absent or unterminated. The JSON we emit never contains `]]`, so
  /// the first terminator is always the right one.
  static String? _payload(String text, String open) {
    final i = text.indexOf(open);
    if (i < 0) return null;
    final start = i + open.length;
    final end = text.indexOf(_close, start);
    if (end < 0) return null;
    return text.substring(start, end);
  }
}
