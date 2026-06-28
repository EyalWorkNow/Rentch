import 'package:dating_app/data/models/rent_ledger.dart';
import 'package:dating_app/data/repositories/rent_ledger_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('month generation', () {
    test('generates N consecutive months from a lease start', () {
      final ledger = RentLedger(propertyId: 'p1').generateMonths(
        start: DateTime(2026, 11),
        count: 4,
        monthlyAmount: 5000,
      );

      expect(ledger.entries.length, 4);
      expect(ledger.entries.first.year, 2026);
      expect(ledger.entries.first.month, 11);
      // Wraps across the year boundary.
      expect(ledger.entries[2].year, 2027);
      expect(ledger.entries[2].month, 1);
      expect(ledger.entries.every((e) => e.amount == 5000), isTrue);
      expect(ledger.entries.every((e) => !e.paid), isTrue);
    });

    test('preserves existing entries (and their paid status) on regeneration',
        () {
      var ledger = RentLedger(propertyId: 'p1').generateMonths(
        start: DateTime(2026, 1),
        count: 2,
        monthlyAmount: 4000,
      );
      ledger = ledger.togglePaidAt(0); // mark Jan paid
      expect(ledger.entries.first.paid, isTrue);

      // Regenerate over an overlapping range with a different amount.
      final regenerated = ledger.generateMonths(
        start: DateTime(2026, 1),
        count: 4,
        monthlyAmount: 9999,
      );

      expect(regenerated.entries.length, 4);
      // Jan kept its paid status AND its original amount.
      final jan = regenerated.entries.first;
      expect(jan.month, 1);
      expect(jan.paid, isTrue);
      expect(jan.amount, 4000);
      // Newly added months use the new amount.
      expect(regenerated.entries.last.amount, 9999);
    });

    test('entries stay sorted oldest to newest', () {
      final ledger = RentLedger(
        propertyId: 'p1',
        entries: [
          const RentEntry(year: 2026, month: 5, amount: 100),
          const RentEntry(year: 2026, month: 1, amount: 100),
          const RentEntry(year: 2025, month: 12, amount: 100),
        ],
      );
      final keys = ledger.entries.map((e) => e.sortKey).toList();
      final sorted = [...keys]..sort();
      expect(keys, sorted);
    });
  });

  group('paid toggle', () {
    test('toggling stamps paidAt, toggling back clears it', () {
      final entry = const RentEntry(year: 2026, month: 6, amount: 5000);
      expect(entry.paid, isFalse);
      expect(entry.paidAt, isNull);

      final paid = entry.toggledPaid(at: DateTime(2026, 6, 15));
      expect(paid.paid, isTrue);
      expect(paid.paidAt, DateTime(2026, 6, 15));

      final unpaid = paid.toggledPaid();
      expect(unpaid.paid, isFalse);
      expect(unpaid.paidAt, isNull);
    });

    test('togglePaidAt updates the right entry in the ledger', () {
      var ledger = RentLedger(propertyId: 'p1').generateMonths(
        start: DateTime(2026, 1),
        count: 3,
        monthlyAmount: 3000,
      );
      ledger = ledger.togglePaidAt(1, at: DateTime(2026, 2, 3));

      expect(ledger.entries[0].paid, isFalse);
      expect(ledger.entries[1].paid, isTrue);
      expect(ledger.entries[1].paidAt, DateTime(2026, 2, 3));
      expect(ledger.entries[2].paid, isFalse);
    });

    test('out-of-range toggle index is a no-op', () {
      final ledger = RentLedger(propertyId: 'p1').generateMonths(
        start: DateTime(2026, 1),
        count: 1,
        monthlyAmount: 1000,
      );
      expect(ledger.togglePaidAt(5).entries.first.paid, isFalse);
      expect(ledger.togglePaidAt(-1).entries.first.paid, isFalse);
    });
  });

  group('overdue / current detection', () {
    final now = DateTime(2026, 6, 15);

    test('past unpaid month is overdue', () {
      const past = RentEntry(year: 2026, month: 4, amount: 5000);
      expect(past.isOverdue(now), isTrue);
    });

    test('past PAID month is not overdue', () {
      final past = const RentEntry(year: 2026, month: 4, amount: 5000)
          .toggledPaid(at: DateTime(2026, 4, 10));
      expect(past.isOverdue(now), isFalse);
    });

    test('current month is not yet overdue', () {
      const current = RentEntry(year: 2026, month: 6, amount: 5000);
      expect(current.isOverdue(now), isFalse);
      expect(current.isCurrent(now), isTrue);
    });

    test('future month is not overdue', () {
      const future = RentEntry(year: 2026, month: 8, amount: 5000);
      expect(future.isOverdue(now), isFalse);
    });

    test('ledger debt sums only past-unpaid months', () {
      var ledger = RentLedger(
        propertyId: 'p1',
        entries: const [
          RentEntry(year: 2026, month: 3, amount: 5000), // overdue
          RentEntry(year: 2026, month: 4, amount: 5000), // overdue
          RentEntry(year: 2026, month: 6, amount: 5000), // current, not overdue
          RentEntry(year: 2026, month: 8, amount: 5000), // future
        ],
      );
      // Pay April off.
      ledger = ledger.upsert(
        ledger.entries[1].toggledPaid(at: DateTime(2026, 4, 5)),
      );

      expect(ledger.outstandingDebt(now), 5000); // only March remains overdue
      expect(ledger.overdueEntries(now).length, 1);
    });

    test('collectedThisMonth reflects current month payment', () {
      var ledger = RentLedger(
        propertyId: 'p1',
        entries: const [RentEntry(year: 2026, month: 6, amount: 4200)],
      );
      expect(ledger.collectedThisMonth(now), 0);
      ledger = ledger.upsert(ledger.entries.first.toggledPaid());
      expect(ledger.collectedThisMonth(now), 4200);
    });
  });

  group('JSON round-trip', () {
    test('entry survives encode/decode including paidAt and note', () {
      final entry = RentEntry(
        year: 2026,
        month: 6,
        amount: 5500,
        paid: true,
        paidAt: DateTime(2026, 6, 12, 9, 30),
        note: 'שילם במזומן',
      );
      final restored = RentEntry.fromJson(entry.toJson());

      expect(restored.year, 2026);
      expect(restored.month, 6);
      expect(restored.amount, 5500);
      expect(restored.paid, isTrue);
      expect(restored.paidAt, DateTime(2026, 6, 12, 9, 30));
      expect(restored.note, 'שילם במזומן');
    });

    test('ledger survives encode/decode', () {
      var ledger = RentLedger(propertyId: 'prop-42').generateMonths(
        start: DateTime(2026, 1),
        count: 6,
        monthlyAmount: 4800,
      );
      ledger = ledger.togglePaidAt(0).togglePaidAt(2);

      final restored = RentLedger.fromJson(ledger.toJson());
      expect(restored.propertyId, 'prop-42');
      expect(restored.entries.length, 6);
      expect(restored.entries[0].paid, isTrue);
      expect(restored.entries[1].paid, isFalse);
      expect(restored.entries[2].paid, isTrue);
      expect(restored.entries.map((e) => e.month).toList(),
          [1, 2, 3, 4, 5, 6]);
    });

    test('fromJson tolerates missing / malformed fields', () {
      final ledger = RentLedger.fromJson({
        'propertyId': 'p1',
        'entries': [
          {'year': '2026', 'month': '5', 'amount': '5000'}, // string numbers
          {'month': 7}, // missing year/amount
          'garbage', // not a map
        ],
      });
      expect(ledger.propertyId, 'p1');
      expect(ledger.entries.length, 2);
      // String numbers are coerced; the well-formed entry is parsed correctly.
      final may = ledger.entries.firstWhere((e) => e.month == 5);
      expect(may.year, 2026);
      expect(may.amount, 5000);
    });
  });

  group('repository persistence', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('save then load round-trips a ledger keyed by propertyId', () async {
      final repo = RentLedgerRepository();
      var ledger = RentLedger(propertyId: 'apt-7').generateMonths(
        start: DateTime(2026, 3),
        count: 3,
        monthlyAmount: 6000,
      );
      ledger = ledger.togglePaidAt(0, at: DateTime(2026, 3, 2));

      await repo.save(ledger);
      final loaded = await repo.load('apt-7');

      expect(loaded.propertyId, 'apt-7');
      expect(loaded.entries.length, 3);
      expect(loaded.entries.first.paid, isTrue);
      expect(loaded.entries.first.paidAt, DateTime(2026, 3, 2));
    });

    test('loading an unknown property returns an empty valid ledger', () async {
      final repo = RentLedgerRepository();
      final loaded = await repo.load('never-saved');
      expect(loaded.propertyId, 'never-saved');
      expect(loaded.isEmpty, isTrue);
    });

    test('ledgers are isolated per property', () async {
      final repo = RentLedgerRepository();
      await repo.save(
        RentLedger(propertyId: 'a').generateMonths(
          start: DateTime(2026, 1),
          count: 2,
          monthlyAmount: 1000,
        ),
      );
      await repo.save(
        RentLedger(propertyId: 'b').generateMonths(
          start: DateTime(2026, 1),
          count: 5,
          monthlyAmount: 2000,
        ),
      );

      expect((await repo.load('a')).entries.length, 2);
      expect((await repo.load('b')).entries.length, 5);
    });

    test('delete removes the stored ledger', () async {
      final repo = RentLedgerRepository();
      await repo.save(
        RentLedger(propertyId: 'c').generateMonths(
          start: DateTime(2026, 1),
          count: 1,
          monthlyAmount: 500,
        ),
      );
      await repo.delete('c');
      expect((await repo.load('c')).isEmpty, isTrue);
    });
  });
}
