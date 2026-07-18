import 'package:dating_app/core/chat/slot_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SlotMessageCodec proposal', () {
    test('round-trips encode → parse', () {
      final proposal = SlotProposal(
        propertyId: 'prop_42',
        options: [
          SlotOption(
            slotId: 's1',
            start: DateTime(2026, 7, 20, 10, 0),
            durationMinutes: 30,
          ),
          SlotOption(
            slotId: 's2',
            start: DateTime(2026, 7, 21, 17, 30),
            durationMinutes: 45,
          ),
        ],
      );

      final encoded = SlotMessageCodec.encodeProposal(proposal);
      final result = SlotMessageCodec.parse(encoded);

      expect(result, isA<SlotProposalMessage>());
      final parsed = (result as SlotProposalMessage).proposal;
      expect(parsed.propertyId, 'prop_42');
      expect(parsed.options.length, 2);
      expect(parsed.options[0].slotId, 's1');
      expect(parsed.options[0].start, DateTime(2026, 7, 20, 10, 0));
      expect(parsed.options[0].durationMinutes, 30);
      expect(parsed.options[1].slotId, 's2');
      expect(parsed.options[1].durationMinutes, 45);
    });

    test('displayText strips the marker', () {
      final encoded = SlotMessageCodec.encodeProposal(
        SlotProposal(
          propertyId: 'p',
          options: [
            SlotOption(
              slotId: 's1',
              start: DateTime(2026, 7, 20, 10, 0),
              durationMinutes: 30,
            ),
          ],
        ),
      );
      final display = SlotMessageCodec.displayText(encoded);
      expect(display.contains('[[SLOTS:'), isFalse);
      expect(display.contains(']]'), isFalse);
      expect(display, 'הצעתי מועד לצפייה בדירה 🗓️');
    });
  });

  group('SlotMessageCodec confirm', () {
    test('round-trips encode → parse', () {
      final confirm = SlotConfirm(
        slotId: 's7',
        start: DateTime(2026, 7, 22, 12, 15),
        durationMinutes: 30,
        propertyId: 'prop_99',
      );

      final encoded = SlotMessageCodec.encodeConfirm(confirm);
      final result = SlotMessageCodec.parse(encoded);

      expect(result, isA<SlotConfirmMessage>());
      final parsed = (result as SlotConfirmMessage).confirm;
      expect(parsed.slotId, 's7');
      expect(parsed.start, DateTime(2026, 7, 22, 12, 15));
      expect(parsed.durationMinutes, 30);
      expect(parsed.propertyId, 'prop_99');
    });

    test('displayText strips the confirm marker', () {
      final encoded = SlotMessageCodec.encodeConfirm(
        SlotConfirm(
          slotId: 's7',
          start: DateTime(2026, 7, 22, 12, 15),
          durationMinutes: 30,
          propertyId: 'p',
        ),
      );
      final display = SlotMessageCodec.displayText(encoded);
      expect(display.contains('[[SLOT_CONFIRM:'), isFalse);
      expect(display, 'אישרתי מועד לצפייה בדירה ✓');
    });
  });

  group('SlotMessageCodec plain / malformed', () {
    test('a plain message parses as plain', () {
      const text = 'שלום, מתי אפשר לבוא לצפות בדירה?';
      expect(SlotMessageCodec.parse(text), isA<SlotPlainMessage>());
      expect(SlotMessageCodec.displayText(text), text);
    });

    test('malformed marker (bad json) falls back to plain', () {
      const text = 'הצעתי מועד\n[[SLOTS:{not valid json}]]';
      expect(SlotMessageCodec.parse(text), isA<SlotPlainMessage>());
    });

    test('unterminated marker falls back to plain', () {
      const text = 'הצעתי מועד\n[[SLOTS:{"propertyId":"p"';
      expect(SlotMessageCodec.parse(text), isA<SlotPlainMessage>());
      // displayText leaves an unterminated marker untouched (still "plain").
      expect(SlotMessageCodec.displayText(text), text.trim());
    });

    test('empty-options proposal is not treated as a proposal', () {
      const text = 'משהו\n[[SLOTS:{"propertyId":"p","options":[]}]]';
      expect(SlotMessageCodec.parse(text), isA<SlotPlainMessage>());
    });
  });
}
