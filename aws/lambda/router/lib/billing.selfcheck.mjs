// Self-check for billing.mjs — run: `node lib/billing.selfcheck.mjs`
// Pure-logic assertions for the entitlement/quota math. No AWS, no network.
import assert from 'node:assert';
import {
  BILLING, planById, addMonths, nextPeriod, hasActiveEntitlement, entitlementView, quotaBlockReason,
  cronAction, dunningAfterFailure, renewedRow,
} from './billing.mjs';

const NOW = Date.parse('2026-08-01T00:00:00Z');
const future = new Date(NOW + 10 * 864e5).toISOString();
const past = new Date(NOW - 10 * 864e5).toISOString();
const S = BILLING.STATUS;

// ── plans ──────────────────────────────────────────────────────────────────
assert.equal(BILLING.FREE_PROPERTY_LIMIT, 3);
assert.equal(planById('monthly').priceAgorot, 3500);
assert.equal(planById('annual').priceAgorot, 35000);
assert.equal(planById('annual').months, 12);
assert.equal(planById('bogus'), null);

// ── addMonths (month-length & overflow) ──────────────────────────────────────
assert.equal(addMonths(Date.parse('2026-01-15T00:00:00Z'), 1).slice(0, 10), '2026-02-15');
assert.equal(addMonths(Date.parse('2026-01-31T00:00:00Z'), 1).slice(0, 10), '2026-02-28'); // clamp
assert.equal(addMonths(Date.parse('2026-03-15T00:00:00Z'), 12).slice(0, 10), '2027-03-15');

// ── nextPeriod (early renewals stack) ────────────────────────────────────────
{
  const monthly = planById('monthly'), annual = planById('annual');
  // fresh (no current period) → from now
  const fresh = nextPeriod(null, monthly, NOW);
  assert.equal(fresh.periodStart.slice(0, 10), '2026-08-01');
  assert.equal(fresh.periodEnd.slice(0, 10), '2026-09-01');
  // renew BEFORE expiry → stacks from current end, not from now
  const stack = nextPeriod({ currentPeriodEnd: future }, monthly, NOW); // future = NOW+10d
  assert.equal(stack.periodEnd.slice(0, 10), '2026-09-11', 'stacks on unexpired period');
  // renew AFTER expiry → from now
  const lapsed = nextPeriod({ currentPeriodEnd: past }, monthly, NOW);
  assert.equal(lapsed.periodEnd.slice(0, 10), '2026-09-01', 'expired → from now');
  // annual
  assert.equal(nextPeriod(null, annual, NOW).periodEnd.slice(0, 10), '2027-08-01');
}

// ── hasActiveEntitlement ─────────────────────────────────────────────────────
assert.equal(hasActiveEntitlement(null, NOW), false, 'no sub → not entitled');
assert.equal(hasActiveEntitlement({ status: S.ACTIVE, currentPeriodEnd: future }, NOW), true);
assert.equal(hasActiveEntitlement({ status: S.ACTIVE, currentPeriodEnd: past }, NOW), false, 'expired period');
assert.equal(hasActiveEntitlement({ status: S.ACTIVE }, NOW), true, 'active w/o end = entitled');
assert.equal(hasActiveEntitlement({ status: S.PAST_DUE, graceUntil: future }, NOW), true, 'past_due in grace');
assert.equal(hasActiveEntitlement({ status: S.PAST_DUE, graceUntil: past }, NOW), false, 'past_due grace over');
assert.equal(hasActiveEntitlement({ status: S.CANCELED }, NOW), false);
assert.equal(hasActiveEntitlement({ status: S.CANCELED, grandfatherUntil: future }, NOW), true, 'grandfather overrides');
assert.equal(hasActiveEntitlement({ status: S.NONE, grandfatherUntil: past }, NOW), false, 'grandfather expired');

// ── quotaBlockReason ─────────────────────────────────────────────────────────
assert.equal(quotaBlockReason(null, 0, NOW), null, '0 props free');
assert.equal(quotaBlockReason(null, 2, NOW), null, '2 props free (3rd allowed)');
assert.ok(quotaBlockReason(null, 3, NOW), '3 active → 4th blocked without sub');
assert.equal(quotaBlockReason(null, 3, NOW).code, 'PROP_LIMIT');
assert.equal(quotaBlockReason({ status: S.ACTIVE, currentPeriodEnd: future }, 8, NOW), null, 'subscribed → unlimited');
assert.equal(quotaBlockReason({ status: S.ACTIVE, currentPeriodEnd: past }, 3, NOW).code, 'PROP_LIMIT', 'expired sub blocks');

// ── entitlementView ──────────────────────────────────────────────────────────
const vFree = entitlementView(null, 2, NOW);
assert.equal(vFree.status, 'none');
assert.equal(vFree.canAddProperty, true);
assert.equal(vFree.freeLimit, 3);
assert.equal(vFree.card, null);

const vFull = entitlementView(null, 3, NOW);
assert.equal(vFull.canAddProperty, false, '3 active, no sub → cannot add');

const vPaid = entitlementView(
  { status: S.ACTIVE, plan: 'annual', currentPeriodEnd: future, cardLast4: '4242', cardBrand: 'visa' },
  9, NOW);
assert.equal(vPaid.canAddProperty, true);
assert.equal(vPaid.plan, 'annual');
assert.equal(vPaid.priceAgorot, 35000);
assert.deepEqual(vPaid.card, { brand: 'visa', last4: '4242' });

// ── renewedRow ───────────────────────────────────────────────────────────────
{
  const monthly = planById('monthly');
  // first payment: charge carries token/card → persisted
  const first = renewedRow({ version: 0 }, monthly, NOW, { transactionId: 't1', token: 'tok', cardLast4: '4242', cardBrand: 'visa' });
  assert.equal(first.status, 'active');
  assert.equal(first.plan, 'monthly');
  assert.equal(first.currentPeriodEnd.slice(0, 10), '2026-09-01');
  assert.equal(first.paymentToken, 'tok');
  assert.equal(first.cardLast4, '4242');
  assert.equal(first.failedAttempts, 0);
  assert.equal(first.graceUntil, null);
  // renewal: no card in charge → prior card preserved, period stacks
  const renew = renewedRow({ currentPeriodEnd: future, paymentToken: 'tok', cardLast4: '4242' }, monthly, NOW, { transactionId: 't2' });
  assert.equal(renew.paymentToken, 'tok', 'token preserved on renewal');
  assert.equal(renew.cardLast4, '4242', 'card preserved on renewal');
  assert.equal(renew.currentPeriodEnd.slice(0, 10), '2026-09-11', 'renewal stacks on unexpired period');
  assert.equal(renew.lastTransactionId, 't2');
}

// ── cronAction ───────────────────────────────────────────────────────────────
assert.equal(cronAction(null, NOW).action, 'noop');
assert.equal(cronAction({ status: S.ACTIVE, currentPeriodEnd: future }, NOW).action, 'noop', 'active, not due');
assert.deepEqual(cronAction({ status: S.ACTIVE, currentPeriodEnd: past }, NOW), { action: 'charge', reason: 'renewal' }, 'active + period ended → renew');
assert.equal(cronAction({ status: S.ACTIVE, currentPeriodEnd: past, cancelAtPeriodEnd: true }, NOW).action, 'lapse', 'canceled-at-end + ended → downgrade');
assert.equal(cronAction({ status: S.ACTIVE, currentPeriodEnd: future, cancelAtPeriodEnd: true }, NOW).action, 'noop', 'canceled-at-end but still in period');
assert.deepEqual(cronAction({ status: S.PAST_DUE, nextRetryAt: past, graceUntil: future }, NOW), { action: 'charge', reason: 'retry' }, 'retry due, still in grace');
assert.equal(cronAction({ status: S.PAST_DUE, nextRetryAt: future, graceUntil: future }, NOW).action, 'noop', 'retry not yet due');
assert.equal(cronAction({ status: S.PAST_DUE, graceUntil: past }, NOW).action, 'lapse', 'grace expired → downgrade');
assert.equal(cronAction({ status: S.CANCELED }, NOW).action, 'noop');

// ── dunningAfterFailure ──────────────────────────────────────────────────────
{
  const f1 = dunningAfterFailure({}, NOW);
  assert.equal(f1.status, S.PAST_DUE);
  assert.equal(f1.failedAttempts, 1);
  assert.equal(f1.nextRetryAt.slice(0, 10), '2026-08-02', '1st fail → retry +1d');
  // grace = sum(1,3,5)+7 = 16 days from first failure
  assert.equal(f1.graceUntil.slice(0, 10), '2026-08-17', 'grace window set once');
  const f2 = dunningAfterFailure({ failedAttempts: 1, graceUntil: f1.graceUntil }, NOW);
  assert.equal(f2.failedAttempts, 2);
  assert.equal(f2.nextRetryAt.slice(0, 10), '2026-08-04', '2nd fail → retry +3d');
  assert.equal(f2.graceUntil, f1.graceUntil, 'grace preserved, not reset');
  const f3 = dunningAfterFailure({ failedAttempts: 2, graceUntil: f1.graceUntil }, NOW);
  assert.equal(f3.nextRetryAt.slice(0, 10), '2026-08-06', '3rd fail → retry +5d');
  const f4 = dunningAfterFailure({ failedAttempts: 3, graceUntil: f1.graceUntil }, NOW);
  assert.equal(f4.failedAttempts, 4);
  assert.equal(f4.nextRetryAt, null, 'retries exhausted → no more retries');
}

console.log('billing.selfcheck: ALL PASS ✓');
