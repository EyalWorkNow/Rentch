import 'package:dating_app/data/models/subscription.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Subscription.fromJson — server entitlement snapshot', () {
    test('free tier: no sub, under limit → can add', () {
      final s = Subscription.fromJson(const {
        'status': 'none',
        'entitled': false,
        'activeProperties': 2,
        'freeLimit': 3,
        'canAddProperty': true,
      });
      expect(s.entitled, isFalse);
      expect(s.canAddProperty, isTrue);
      expect(s.freeLimit, 3);
      expect(s.card, isNull);
    });

    test('at the limit, unsubscribed → cannot add', () {
      final s = Subscription.fromJson(const {
        'status': 'none',
        'entitled': false,
        'activeProperties': 3,
        'freeLimit': 3,
        'canAddProperty': false,
      });
      expect(s.canAddProperty, isFalse);
    });

    test('active annual subscriber → can add, card + price parsed', () {
      final s = Subscription.fromJson(const {
        'status': 'active',
        'plan': 'annual',
        'priceAgorot': 35000,
        'currentPeriodEnd': '2027-08-01T00:00:00.000Z',
        'cancelAtPeriodEnd': false,
        'card': {'brand': 'visa', 'last4': '4242'},
        'entitled': true,
        'activeProperties': 9,
        'freeLimit': 3,
        'canAddProperty': true,
      });
      expect(s.entitled, isTrue);
      expect(s.plan, 'annual');
      expect(s.priceAgorot, 35000);
      expect(s.canAddProperty, isTrue);
      expect(s.card?.last4, '4242');
      expect(s.cancelAtPeriodEnd, isFalse);
    });

    test('canAddProperty falls back to entitled || under-limit when flag omitted', () {
      final entitled = Subscription.fromJson(const {
        'status': 'active', 'entitled': true, 'activeProperties': 8, 'freeLimit': 3,
      });
      expect(entitled.canAddProperty, isTrue, reason: 'entitled → can add');
      final free = Subscription.fromJson(const {
        'status': 'none', 'entitled': false, 'activeProperties': 1, 'freeLimit': 3,
      });
      expect(free.canAddProperty, isTrue, reason: 'under free limit → can add');
      final blocked = Subscription.fromJson(const {
        'status': 'none', 'entitled': false, 'activeProperties': 3, 'freeLimit': 3,
      });
      expect(blocked.canAddProperty, isFalse, reason: 'at limit, not entitled → blocked');
    });

    test('lossless toJson → fromJson round-trip (persisted snapshot)', () {
      final orig = Subscription.fromJson(const {
        'status': 'active',
        'plan': 'monthly',
        'priceAgorot': 3500,
        'currentPeriodEnd': '2026-09-01T00:00:00.000Z',
        'cancelAtPeriodEnd': true,
        'card': {'brand': 'mastercard', 'last4': '1111'},
        'entitled': true,
        'activeProperties': 5,
        'freeLimit': 3,
        'canAddProperty': true,
      });
      final round = Subscription.fromJson(orig.toJson());
      expect(round.status, orig.status);
      expect(round.plan, orig.plan);
      expect(round.priceAgorot, orig.priceAgorot);
      expect(round.cancelAtPeriodEnd, orig.cancelAtPeriodEnd);
      expect(round.card?.last4, orig.card?.last4);
      expect(round.canAddProperty, orig.canAddProperty);
    });

    test('does not throw on empty / minimal json', () {
      expect(() => Subscription.fromJson(const {}), returnsNormally);
      final s = Subscription.fromJson(const {});
      expect(s.card, isNull);
    });
  });
}
