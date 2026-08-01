// End-to-end self-check for the subscription engine — run:
//   node lib/subscription_engine.selfcheck.mjs
// Drives the FULL lifecycle (checkout → webhook activation → renewal → dunning →
// downgrade → cancel/resume → gate → grandfather → concurrency) against an
// in-memory store + a fake Morning provider. No AWS, no network.
import assert from 'node:assert';
import { createEngine } from './subscription_engine.mjs';
import { BILLING, hasActiveEntitlement } from './billing.mjs';
import { parseWebhook } from './morning.mjs'; // exercise the real parse→apply seam

// ── controllable clock ───────────────────────────────────────────────────────
let clock = Date.parse('2026-09-01T00:00:00Z');
const now = () => clock;
const advanceDays = (d) => { clock += d * 864e5; };

// ── in-memory store ──────────────────────────────────────────────────────────
function makeStore() {
  const subs = new Map();      // uid -> row
  const invoices = new Map();  // id -> item
  const props = new Map();     // uid -> [{id, createdAt, status}]
  let failCas = 0;             // force N cas conflicts (concurrency test)
  return {
    _subs: subs, _invoices: invoices, _props: props,
    _forceCasConflicts(n) { failCas = n; },
    seedProps(uid, list) { props.set(uid, list.map((p) => ({ status: 'active', ...p }))); },
    async getSubscription(uid) { return subs.get(uid) || null; },
    async casPutSubscription(uid, expectedVersion, row) {
      if (failCas > 0) { failCas--; return false; } // simulate a lost race → engine retries
      const cur = subs.get(uid);
      const curV = cur ? (Number(cur.version) || 0) : 0;
      if (curV !== expectedVersion) return false;
      subs.set(uid, row);
      return true;
    },
    async putInvoice(item) {
      if (invoices.has(item.id)) return false; // idempotent
      invoices.set(item.id, item);
      return true;
    },
    async hasInvoice(id) { return invoices.has(String(id)); },
    async listInvoices(uid) {
      return [...invoices.values()].filter((i) => i.ownerUserId === uid)
        .sort((a, b) => (a.issuedAt < b.issuedAt ? 1 : -1));
    },
    async countActiveProperties(uid) {
      return (props.get(uid) || []).filter((p) => p.status !== 'removed' && p.status !== 'paused').length;
    },
    async listActivePropertiesOldestFirst(uid) {
      return (props.get(uid) || []).filter((p) => p.status !== 'removed' && p.status !== 'paused')
        .sort((a, b) => (a.createdAt < b.createdAt ? -1 : 1));
    },
    async pauseProperty(id) {
      for (const list of props.values()) { const p = list.find((x) => x.id === id); if (p) p.status = 'paused'; }
    },
    async *scanSubscriptions() { for (const row of subs.values()) yield row; },
    async ownerActiveCounts() {
      const m = new Map();
      for (const [uid, list] of props) m.set(uid, list.filter((p) => p.status !== 'removed' && p.status !== 'paused').length);
      return m;
    },
  };
}

// ── fake Morning provider ────────────────────────────────────────────────────
function makeProvider() {
  let charge = { ok: true }; // default: successful token charge
  const forms = [];
  const idempSeen = new Set();
  let tx = 0;
  return {
    _setCharge(c) { charge = c; },
    _realCharges: () => tx, // count of REAL (non-deduped) successful token charges
    _forms: forms,
    async upsertClient({ email }) { return `client_${email || 'x'}`; },
    async createPaymentForm(opts) { forms.push(opts); return { url: `https://pay/${opts.subscriptionId}` }; },
    async createPaymentFormOneOff(opts) { forms.push(opts); return { url: `https://pay-oneoff/${opts.custom}` }; },
    async chargeToken({ idempotencyKey }) {
      // provider-side idempotency: a repeated key for an ALREADY-CAPTURED charge
      // returns the same success (no double charge). Declines are not recorded,
      // so a later retry of the same key can genuinely succeed.
      if (idempotencyKey && idempSeen.has(idempotencyKey)) return { ok: true, transactionId: `dup_${idempotencyKey}` };
      if (!charge.ok) return { ok: false };
      if (idempotencyKey) idempSeen.add(idempotencyKey);
      tx += 1;
      return { ok: true, transactionId: `cron_tx_${tx}`, docId: `doc_${tx}`, docUrl: `https://inv/${tx}` };
    },
  };
}

const urls = { successUrl: 'https://ok', failureUrl: 'https://no', notifyUrl: 'https://ipn' };
// simulate parseWebhook output for a paid link "<uid>::<plan>"
const ipn = (uid, plan, txId, amountAgorot, extra = {}) => ({
  subscriptionId: uid, planId: plan, transactionId: txId,
  amountAgorot, success: true, token: 'tok_card', cardLast4: '4242', cardBrand: 'visa',
  docId: `d_${txId}`, docUrl: `https://inv/${txId}`, ...extra,
});

let PASS = 0;
const ok = (label) => { PASS++; };

// ═══════════════════════════════════════════════════════════════════════════
// 1. FREE TIER + GATE
// ═══════════════════════════════════════════════════════════════════════════
{
  const store = makeStore(); const provider = makeProvider();
  const e = createEngine({ store, provider, now });
  const uid = 'L1';
  store.seedProps(uid, []);
  assert.equal(await e.enforceQuota(uid), null, '0 props → allow');
  store.seedProps(uid, [{ id: 'p1', createdAt: '2026-01-01' }, { id: 'p2', createdAt: '2026-01-02' }]);
  assert.equal(await e.enforceQuota(uid), null, '2 props → allow (3rd)');
  let ent = await e.getEntitlement(uid);
  assert.equal(ent.canAddProperty, true); assert.equal(ent.activeProperties, 2);
  store.seedProps(uid, [{ id: 'p1', createdAt: '1' }, { id: 'p2', createdAt: '2' }, { id: 'p3', createdAt: '3' }]);
  const block = await e.enforceQuota(uid);
  assert.ok(block && block.code === 'PROP_LIMIT', '3 active → 4th blocked');
  ent = await e.getEntitlement(uid);
  assert.equal(ent.canAddProperty, false, 'entitlement view says cannot add');
  ok('free tier gate');
}

// ═══════════════════════════════════════════════════════════════════════════
// 2. CHECKOUT → WEBHOOK ACTIVATION → INVOICE
// ═══════════════════════════════════════════════════════════════════════════
const store = makeStore(); const provider = makeProvider();
const e = createEngine({ store, provider, now });
const uid = 'L2';
store.seedProps(uid, [{ id: 'a', createdAt: '1' }, { id: 'b', createdAt: '2' }, { id: 'c', createdAt: '3' }, { id: 'd', createdAt: '4' }]);
{
  const bad = await e.checkout(uid, { plan: 'bogus', ...urls });
  assert.equal(bad.error, 'bad_plan', 'invalid plan rejected');
  const co = await e.checkout(uid, { plan: 'monthly', email: 'l2@x.com', name: 'דנה', ...urls });
  assert.ok(co.url.includes('L2::monthly'), 'checkout returns url with bound plan');
  const sub = await store.getSubscription(uid);
  assert.equal(sub.pendingPlan, 'monthly'); assert.ok(sub.morningClientId, 'client stored');
  // 4th property still blocked (not active yet)
  assert.ok(await e.enforceQuota(uid), 'over limit, not yet paid → blocked');
  ok('checkout');

  const r = await e.applyPayment(ipn(uid, 'monthly', 'tx1', 3500));
  assert.equal(r.activated, true); assert.equal(r.plan, 'monthly');
  assert.equal(r.periodEnd.slice(0, 10), '2026-10-01', 'monthly period +1mo');
  const sub2 = await store.getSubscription(uid);
  assert.equal(sub2.status, 'active'); assert.equal(sub2.cardLast4, '4242');
  assert.equal(sub2.paymentToken, 'tok_card'); assert.equal(sub2.pendingPlan, null);
  const inv = await e.listInvoices(uid);
  assert.equal(inv.length, 1); assert.equal(inv[0].sumAgorot, 3500);
  // now entitled → the 4th property is allowed
  assert.equal(await e.enforceQuota(uid), null, 'subscribed → 4th allowed');
  ok('webhook activation + invoice');
}

// ═══════════════════════════════════════════════════════════════════════════
// 3. IDEMPOTENCY + AMOUNT MISMATCH
// ═══════════════════════════════════════════════════════════════════════════
{
  const dup = await e.applyPayment(ipn(uid, 'monthly', 'tx1', 3500));
  assert.equal(dup.ignored, 'duplicate', 'duplicate tx ignored');
  assert.equal((await e.listInvoices(uid)).length, 1, 'no second invoice');
  const mism = await e.applyPayment(ipn(uid, 'monthly', 'tx_bad', 100));
  assert.equal(mism.ignored, 'amount_mismatch', 'wrong amount refused');
  const sub = await store.getSubscription(uid);
  assert.equal(sub.lastTransactionId, 'tx1', 'mismatch did not activate');
  ok('idempotency + amount cross-check');
}

// ═══════════════════════════════════════════════════════════════════════════
// 4. EARLY-RENEWAL STACKING (2nd payment before period end)
// ═══════════════════════════════════════════════════════════════════════════
{
  const before = await store.getSubscription(uid); // ends 2026-10-01
  const r = await e.applyPayment(ipn(uid, 'monthly', 'tx2', 3500));
  assert.equal(r.periodEnd.slice(0, 10), '2026-11-01', 'early renewal STACKS (+1mo on existing end)');
  assert.equal((await e.listInvoices(uid)).length, 2);
  ok('early-renewal stacking');
}

// ═══════════════════════════════════════════════════════════════════════════
// 5. CRON RENEWAL + double-run same-day safety
// ═══════════════════════════════════════════════════════════════════════════
{
  clock = Date.parse('2026-11-01T03:00:00Z'); // at/after period end
  const s1 = await e.runCron();
  assert.equal(s1.charged, 1, 'cron renews the due sub');
  const sub = await store.getSubscription(uid);
  assert.equal(sub.status, 'active');
  assert.equal(sub.currentPeriodEnd.slice(0, 10), '2026-12-01', 'cron extended +1mo');
  const invCount = (await e.listInvoices(uid)).length;
  assert.equal(invCount, 3, 'renewal invoice recorded');
  // same-day second run → no double charge
  const s2 = await e.runCron();
  assert.equal(s2.charged, 0, 'same-day re-run does not re-charge');
  assert.equal((await e.listInvoices(uid)).length, 3, 'no duplicate invoice');
  ok('cron renewal + double-run guard');
}

// ═══════════════════════════════════════════════════════════════════════════
// 6. DUNNING → PAST_DUE → GRACE → LAPSE → DOWNGRADE (pause newest first)
// ═══════════════════════════════════════════════════════════════════════════
{
  provider._setCharge({ ok: false }); // all charges now decline
  clock = Date.parse('2026-12-01T03:00:00Z'); // renewal due
  const s1 = await e.runCron();
  assert.equal(s1.failed, 1, 'charge declined → dunning');
  let sub = await store.getSubscription(uid);
  assert.equal(sub.status, 'past_due'); assert.equal(sub.failedAttempts, 1);
  assert.ok(sub.graceUntil, 'grace window set');
  // still entitled during grace
  assert.equal(await e.enforceQuota(uid), null, 'past_due within grace → still entitled');
  // advance to grace expiry → lapse + downgrade
  clock = Date.parse('2026-12-20T03:00:00Z'); // > graceUntil (16d from 12-01)
  const s2 = await e.runCron();
  assert.equal(s2.lapsed, 1, 'grace expired → lapse');
  sub = await store.getSubscription(uid);
  assert.equal(sub.status, 'canceled');
  // downgrade paused the newest properties beyond 3 (had a,b,c,d → pause d)
  const active = await store.listActivePropertiesOldestFirst(uid);
  assert.deepEqual(active.map((p) => p.id), ['a', 'b', 'c'], 'kept oldest 3');
  assert.equal(store._props.get(uid).find((p) => p.id === 'd').status, 'paused', 'newest (d) paused');
  // no longer entitled
  assert.ok(await e.enforceQuota(uid), 'canceled → gate blocks again');
  ok('dunning → lapse → downgrade newest-first');
}

// ═══════════════════════════════════════════════════════════════════════════
// 7. CANCEL AT PERIOD END + RESUME
// ═══════════════════════════════════════════════════════════════════════════
{
  const store2 = makeStore(); const provider2 = makeProvider();
  const e2 = createEngine({ store: store2, provider: provider2, now });
  const u = 'L7';
  store2.seedProps(u, [{ id: 'x', createdAt: '1' }]);
  clock = Date.parse('2027-01-01T00:00:00Z');
  await e2.checkout(u, { plan: 'annual', email: 'l7@x.com', ...urls });
  await e2.applyPayment(ipn(u, 'annual', 'a1', 35000));
  let sub = await store2.getSubscription(u);
  assert.equal(sub.plan, 'annual');
  assert.equal(sub.currentPeriodEnd.slice(0, 10), '2028-01-01', 'annual +12mo');
  // cancel → stays entitled until period end
  await e2.cancel(u);
  sub = await store2.getSubscription(u);
  assert.equal(sub.cancelAtPeriodEnd, true);
  assert.equal(await e2.enforceQuota(u === u ? u : u), null); // still entitled (annual not ended)
  // resume → cancel cleared
  await e2.resume(u);
  assert.equal((await store2.getSubscription(u)).cancelAtPeriodEnd, false);
  // cancel again, advance past period end → cron lapses
  await e2.cancel(u);
  clock = Date.parse('2028-01-02T03:00:00Z');
  const s = await e2.runCron();
  assert.equal(s.lapsed, 1, 'canceled + period ended → lapse');
  assert.equal((await store2.getSubscription(u)).status, 'canceled');
  ok('cancel-at-period-end + resume');
}

// ═══════════════════════════════════════════════════════════════════════════
// 8. GRANDFATHER existing >3 owners
// ═══════════════════════════════════════════════════════════════════════════
{
  const store3 = makeStore(); const provider3 = makeProvider();
  const e3 = createEngine({ store: store3, provider: provider3, now });
  clock = Date.parse('2026-09-01T00:00:00Z');
  store3.seedProps('big', [1, 2, 3, 4, 5].map((n) => ({ id: `p${n}`, createdAt: `${n}` })));
  store3.seedProps('small', [{ id: 'q1', createdAt: '1' }]);
  const res = await e3.grandfather(30);
  assert.equal(res.stamped, 1, 'only the >3 owner grandfathered');
  const bigSub = await store3.getSubscription('big');
  assert.ok(bigSub.grandfatherUntil, 'grandfather stamped');
  assert.equal(await e3.enforceQuota('big'), null, 'grandfathered → allowed to keep >3');
  assert.equal(await store3.getSubscription('small'), null, 'small owner untouched');
  // after the window, gate re-applies
  clock = Date.parse('2026-10-15T00:00:00Z'); // >30d later
  assert.ok(await e3.enforceQuota('big'), 'grandfather expired → gate blocks');
  ok('grandfather rollout');
}

// ═══════════════════════════════════════════════════════════════════════════
// 9. CONCURRENCY — version conflict forces a retry, state stays correct
// ═══════════════════════════════════════════════════════════════════════════
{
  const store4 = makeStore(); const provider4 = makeProvider();
  const e4 = createEngine({ store: store4, provider: provider4, now });
  const u = 'L9';
  store4.seedProps(u, [{ id: 'z', createdAt: '1' }]);
  clock = Date.parse('2026-09-01T00:00:00Z');
  await e4.checkout(u, { plan: 'monthly', email: 'l9@x.com', ...urls });
  store4._forceCasConflicts(2); // first 2 cas writes "lose the race" → engine retries
  const r = await e4.applyPayment(ipn(u, 'monthly', 'c1', 3500));
  assert.equal(r.activated, true, 'activates despite 2 version conflicts (retry works)');
  assert.equal((await store4.getSubscription(u)).status, 'active');
  ok('optimistic-concurrency retry');
}

// ═══════════════════════════════════════════════════════════════════════════
// 10. ANNUAL plan — full lifecycle + renewal after 12 months
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  const u = 'ann'; s.seedProps(u, []);
  clock = Date.parse('2027-03-15T00:00:00Z');
  await en.checkout(u, { plan: 'annual', email: 'a@x.com', ...urls });
  const r = await en.applyPayment(ipn(u, 'annual', 'A1', 35000));
  assert.equal(r.plan, 'annual');
  assert.equal(r.periodEnd.slice(0, 10), '2028-03-15', 'annual +12mo');
  assert.equal((await en.listInvoices(u))[0].sumAgorot, 35000);
  clock = Date.parse('2027-09-01T03:00:00Z'); // mid-year
  assert.equal((await en.runCron()).noop, 1, 'annual not due mid-year');
  clock = Date.parse('2028-03-15T03:00:00Z'); // a year later
  assert.equal((await en.runCron()).charged, 1, 'annual renews at 12mo');
  assert.equal((await s.getSubscription(u)).currentPeriodEnd.slice(0, 10), '2029-03-15', 'renewed +12mo');
  ok('annual lifecycle + renewal');
}

// ═══════════════════════════════════════════════════════════════════════════
// 11. DUNNING RECOVERY — a failed charge, then a retry SUCCEEDS → back to active
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  const u = 'rec'; s.seedProps(u, [1, 2, 3, 4].map((n) => ({ id: `p${n}`, createdAt: `${n}` })));
  clock = Date.parse('2026-09-01T00:00:00Z');
  await en.checkout(u, { plan: 'monthly', email: 'r@x.com', ...urls });
  await en.applyPayment(ipn(u, 'monthly', 'R1', 3500));
  p._setCharge({ ok: false });                       // renewal will decline
  clock = Date.parse('2026-10-01T03:00:00Z');
  await en.runCron();
  let sub = await s.getSubscription(u);
  assert.equal(sub.status, 'past_due'); assert.equal(sub.failedAttempts, 1);
  p._setCharge({ ok: true });                        // card fixed
  clock = Date.parse('2026-10-02T03:00:00Z');        // retry day (+1d)
  assert.equal((await en.runCron()).charged, 1, 'retry succeeds');
  sub = await s.getSubscription(u);
  assert.equal(sub.status, 'active', 'recovered to active');
  assert.equal(sub.failedAttempts, 0, 'dunning attempts cleared');
  assert.equal(sub.graceUntil, null, 'grace cleared');
  assert.equal(sub.nextRetryAt, null, 'retry cleared');
  assert.equal((await s.listActivePropertiesOldestFirst(u)).length, 4, 'no property ever paused');
  ok('dunning recovery');
}

// ═══════════════════════════════════════════════════════════════════════════
// 12. DOWNGRADE edge — owner with ≤3 active pauses NOTHING
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  const u = 'few'; s.seedProps(u, [{ id: 'a', createdAt: '1' }, { id: 'b', createdAt: '2' }]);
  clock = Date.parse('2026-09-01T00:00:00Z');
  await en.checkout(u, { plan: 'monthly', email: 'f@x.com', ...urls });
  await en.applyPayment(ipn(u, 'monthly', 'F1', 3500));
  await en.cancel(u);
  clock = Date.parse('2026-10-02T03:00:00Z');
  assert.equal((await en.runCron()).lapsed, 1);
  assert.equal((await s.listActivePropertiesOldestFirst(u)).length, 2, '≤3 props → none paused');
  ok('downgrade with ≤3 props pauses nothing');
}

// ═══════════════════════════════════════════════════════════════════════════
// 13. DOWNGRADE — 6 active → pause 3, keep the OLDEST 3
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  const u = 'many'; s.seedProps(u, [1, 2, 3, 4, 5, 6].map((n) => ({ id: `p${n}`, createdAt: `2026-0${n}` })));
  clock = Date.parse('2026-09-01T00:00:00Z');
  await en.checkout(u, { plan: 'monthly', email: 'm@x.com', ...urls });
  await en.applyPayment(ipn(u, 'monthly', 'M1', 3500));
  await en.cancel(u);
  clock = Date.parse('2026-10-02T03:00:00Z');
  await en.runCron();
  const active = await s.listActivePropertiesOldestFirst(u);
  assert.deepEqual(active.map((x) => x.id), ['p1', 'p2', 'p3'], 'keeps the oldest 3');
  ok('downgrade 6 → pause 3 (keep oldest)');
}

// ═══════════════════════════════════════════════════════════════════════════
// 14. FAIL-OPEN — a store count error (-1) never blocks a publish
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  s.countActiveProperties = async () => -1; // simulate a transient DynamoDB error
  assert.equal(await en.enforceQuota('err'), null, 'count error → fail OPEN (allow)');
  const ent = await en.getEntitlement('err');
  assert.equal(ent.activeProperties, 0, '-1 clamped to 0 in the view');
  ok('fail-open on store error');
}

// ═══════════════════════════════════════════════════════════════════════════
// 15. PLAN FALLBACK — a legacy IPN with no plan in `custom` uses pendingPlan
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  const u = 'leg'; s.seedProps(u, []);
  clock = Date.parse('2026-09-01T00:00:00Z');
  await en.checkout(u, { plan: 'annual', email: 'l@x.com', ...urls }); // pendingPlan=annual
  const r = await en.applyPayment({ subscriptionId: u, planId: null, transactionId: 'L1', amountAgorot: 35000, success: true, token: 't' });
  assert.equal(r.plan, 'annual', 'falls back to pendingPlan when custom carries no plan');
  ok('plan fallback to pendingPlan');
}

// ═══════════════════════════════════════════════════════════════════════════
// 16. UNSUCCESSFUL webhook — success:false never activates
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  const u = 'nos'; s.seedProps(u, []);
  await en.checkout(u, { plan: 'monthly', email: 'n@x.com', ...urls });
  const r = await en.applyPayment({ subscriptionId: u, planId: 'monthly', success: false, transactionId: 'N1' });
  assert.equal(r.ignored, 'not_successful');
  assert.equal((await s.getSubscription(u)).status, 'none', 'failed payment did not activate');
  assert.equal((await en.listInvoices(u)).length, 0, 'no invoice on failure');
  ok('unsuccessful webhook ignored');
}

// ═══════════════════════════════════════════════════════════════════════════
// 17. GRANDFATHER — idempotent + never overrides an ACTIVE subscriber
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  clock = Date.parse('2026-09-01T00:00:00Z');
  s.seedProps('gf1', [1, 2, 3, 4].map((n) => ({ id: `a${n}`, createdAt: `${n}` })));       // >3, no sub
  s.seedProps('gf2', [1, 2, 3, 4, 5].map((n) => ({ id: `b${n}`, createdAt: `${n}` })));    // >3, will be active
  await en.checkout('gf2', { plan: 'monthly', email: 'g@x.com', ...urls });
  await en.applyPayment(ipn('gf2', 'monthly', 'G1', 3500));
  const r1 = await en.grandfather(30);
  assert.equal(r1.stamped, 1, 'only gf1 grandfathered (gf2 active → skipped)');
  const until1 = (await s.getSubscription('gf1')).grandfatherUntil;
  assert.ok(until1);
  const r2 = await en.grandfather(30);
  assert.equal(r2.stamped, 0, 'second run is idempotent');
  assert.equal((await s.getSubscription('gf1')).grandfatherUntil, until1, 'not re-stamped');
  assert.equal((await s.getSubscription('gf2')).status, 'active', 'active subscriber untouched');
  ok('grandfather idempotent + skips active');
}

// ═══════════════════════════════════════════════════════════════════════════
// 18. MULTI-OWNER cron run — renew, renew, lapse in one pass
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  clock = Date.parse('2026-09-01T00:00:00Z');
  for (const o of ['o1', 'o2', 'o3']) {
    s.seedProps(o, [{ id: `${o}p`, createdAt: '1' }]);
    await en.checkout(o, { plan: 'monthly', email: `${o}@x.com`, ...urls });
    await en.applyPayment(ipn(o, 'monthly', `${o}tx`, 3500));
  }
  await en.cancel('o3'); // o3 will lapse at period end
  clock = Date.parse('2026-10-02T03:00:00Z'); // all periods ended
  const st = await en.runCron();
  assert.equal(st.processed, 3);
  assert.equal(st.charged, 2, 'o1 + o2 renewed');
  assert.equal(st.lapsed, 1, 'o3 (canceled) lapsed');
  assert.equal((await s.getSubscription('o3')).status, 'canceled');
  ok('multi-owner cron pass');
}

// ═══════════════════════════════════════════════════════════════════════════
// 19. NO-TOKEN renewal → straight to dunning (can't charge)
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  const u = 'ntk'; s.seedProps(u, []);
  clock = Date.parse('2026-09-01T00:00:00Z');
  await en.checkout(u, { plan: 'monthly', email: 'nt@x.com', ...urls });
  await en.applyPayment({ subscriptionId: u, planId: 'monthly', transactionId: 'NT1', amountAgorot: 3500, success: true, token: null });
  assert.equal((await s.getSubscription(u)).paymentToken, null, 'no token saved');
  clock = Date.parse('2026-10-01T03:00:00Z');
  assert.equal((await en.runCron()).failed, 1, 'no token → dunning');
  assert.equal((await s.getSubscription(u)).status, 'past_due');
  ok('no-token renewal → dunning');
}

// ═══════════════════════════════════════════════════════════════════════════
// 20. CHECKOUT reuses the Morning client (no duplicate client creation)
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  let upserts = 0; const orig = p.upsertClient; p.upsertClient = async (o) => { upserts++; return orig(o); };
  const u = 'reuse'; s.seedProps(u, []);
  clock = Date.parse('2026-09-01T00:00:00Z');
  await en.checkout(u, { plan: 'monthly', email: 'ru@x.com', ...urls });
  await en.checkout(u, { plan: 'annual', email: 'ru@x.com', ...urls });
  assert.equal(upserts, 1, 'client created once, reused on the 2nd checkout');
  ok('checkout reuses morningClientId');
}

// ═══════════════════════════════════════════════════════════════════════════
// 21. CROSS-PLAN amount mismatch — paying the monthly price for an annual link
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  const u = 'am'; s.seedProps(u, []);
  await en.checkout(u, { plan: 'annual', email: 'am@x.com', ...urls });
  const r = await en.applyPayment(ipn(u, 'annual', 'AM1', 3500)); // ₪35 for an annual (₪350) link
  assert.equal(r.ignored, 'amount_mismatch');
  assert.equal((await s.getSubscription(u)).status, 'none', 'annual NOT granted for the monthly price');
  ok('cross-plan amount mismatch refused');
}

// ═══════════════════════════════════════════════════════════════════════════
// 22. FULL DUNNING LADDER — fail×4 (retries 1/3/5), exhaust, grace, then lapse
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  const u = 'ladder'; s.seedProps(u, [1, 2, 3, 4].map((n) => ({ id: `p${n}`, createdAt: `${n}` })));
  clock = Date.parse('2026-09-01T00:00:00Z');
  await en.checkout(u, { plan: 'monthly', email: 'ld@x.com', ...urls });
  await en.applyPayment(ipn(u, 'monthly', 'LD1', 3500));
  p._setCharge({ ok: false });
  const runAt = (d) => { clock = Date.parse(d); return en.runCron(); };
  await runAt('2026-10-01T03:00:00Z'); // fail 1 (period end)
  let sub = await s.getSubscription(u);
  assert.equal(sub.failedAttempts, 1); assert.equal(sub.nextRetryAt.slice(0, 10), '2026-10-02');
  assert.equal(sub.graceUntil.slice(0, 10), '2026-10-17', 'grace = firstFail + sum(1,3,5)+7');
  await runAt('2026-10-02T03:00:00Z'); // fail 2
  sub = await s.getSubscription(u);
  assert.equal(sub.failedAttempts, 2); assert.equal(sub.nextRetryAt.slice(0, 10), '2026-10-05');
  await runAt('2026-10-05T03:00:00Z'); // fail 3
  sub = await s.getSubscription(u);
  assert.equal(sub.failedAttempts, 3); assert.equal(sub.nextRetryAt.slice(0, 10), '2026-10-10');
  await runAt('2026-10-10T03:00:00Z'); // fail 4 → retries exhausted
  sub = await s.getSubscription(u);
  assert.equal(sub.failedAttempts, 4); assert.equal(sub.nextRetryAt, null, 'retries exhausted');
  assert.equal(sub.status, 'past_due');
  assert.equal(await en.enforceQuota(u), null, 'still entitled inside grace');
  await runAt('2026-10-18T03:00:00Z'); // > grace → lapse
  assert.equal((await s.getSubscription(u)).status, 'canceled');
  assert.deepEqual((await s.listActivePropertiesOldestFirst(u)).map((x) => x.id), ['p1', 'p2', 'p3'], 'downgraded on lapse');
  assert.ok(await en.enforceQuota(u), 'lapsed → gate blocks');
  ok('full dunning ladder → lapse');
}

// ═══════════════════════════════════════════════════════════════════════════
// 23. RE-SUBSCRIBE after a lapse → active again, cancel flag reset
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  const u = 'resub'; s.seedProps(u, [{ id: 'x', createdAt: '1' }]);
  clock = Date.parse('2026-09-01T00:00:00Z');
  await en.checkout(u, { plan: 'monthly', email: 'rs@x.com', ...urls });
  await en.applyPayment(ipn(u, 'monthly', 'RS1', 3500));
  await en.cancel(u);
  clock = Date.parse('2026-10-02T03:00:00Z');
  await en.runCron();
  assert.equal((await s.getSubscription(u)).status, 'canceled');
  await en.checkout(u, { plan: 'monthly', email: 'rs@x.com', ...urls });
  const r = await en.applyPayment(ipn(u, 'monthly', 'RS2', 3500));
  assert.equal(r.activated, true);
  const sub = await s.getSubscription(u);
  assert.equal(sub.status, 'active', 're-subscribed → active');
  assert.equal(sub.cancelAtPeriodEnd, false, 'cancel flag reset');
  ok('re-subscribe after lapse');
}

// ═══════════════════════════════════════════════════════════════════════════
// 24. PERSISTENT write conflict → no activation, no phantom invoice
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  const u = 'conf'; s.seedProps(u, []);
  await en.checkout(u, { plan: 'monthly', email: 'c@x.com', ...urls });
  s._forceCasConflicts(99); // every write loses the race → retries exhaust
  const r = await en.applyPayment(ipn(u, 'monthly', 'CF1', 3500));
  assert.equal(r.ignored, 'no_write', 'could not commit → no activation');
  assert.equal((await en.listInvoices(u)).length, 0, 'no invoice written when activation failed');
  ok('persistent conflict → no phantom invoice');
}

// ═══════════════════════════════════════════════════════════════════════════
// 25. AMOUNT-NULL IPN — provider omits amount → skip cross-check, activate
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  const u = 'noamt'; s.seedProps(u, []);
  clock = Date.parse('2026-09-01T00:00:00Z');
  await en.checkout(u, { plan: 'monthly', email: 'na@x.com', ...urls });
  const r = await en.applyPayment({ subscriptionId: u, planId: 'monthly', transactionId: 'NA1', amountAgorot: null, success: true, token: 't' });
  assert.equal(r.activated, true, 'amount null → no cross-check, activate on the bound plan');
  ok('amount-null IPN activates');
}

// ═══════════════════════════════════════════════════════════════════════════
// 26. ENTITLEMENT VIEW completeness after activation
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  const u = 'view'; s.seedProps(u, [{ id: 'a', createdAt: '1' }]);
  clock = Date.parse('2026-09-01T00:00:00Z');
  await en.checkout(u, { plan: 'annual', email: 'v@x.com', ...urls });
  await en.applyPayment(ipn(u, 'annual', 'V1', 35000));
  const ent = await en.getEntitlement(u);
  assert.equal(ent.status, 'active');
  assert.equal(ent.plan, 'annual');
  assert.equal(ent.priceAgorot, 35000);
  assert.equal(ent.entitled, true);
  assert.equal(ent.canAddProperty, true);
  assert.deepEqual(ent.card, { brand: 'visa', last4: '4242' });
  assert.equal(ent.currentPeriodEnd.slice(0, 10), '2027-09-01');
  assert.equal(ent.cancelAtPeriodEnd, false);
  assert.equal(ent.activeProperties, 1);
  ok('entitlement view completeness');
}

// ═══════════════════════════════════════════════════════════════════════════
// 27. WEBHOOK CHAIN — real parseWebhook(IPN) → engine.applyPayment (router seam)
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  const u = 'chain'; s.seedProps(u, [{ id: 'a', createdAt: '1' }]);
  clock = Date.parse('2026-09-01T00:00:00Z');
  await en.checkout(u, { plan: 'monthly', email: 'ch@x.com', ...urls });
  // the exact payload Green Invoice/Grow POSTs — `custom` round-trips as "uid::plan"
  const payload = {
    status: 1, custom: `${u}::monthly`, token: 'tok_real', cardSuffix: '1234',
    cardBrand: 'mastercard', transactionId: 'CHAIN1', documentId: 'doc_chain',
    documentUrl: 'https://inv/chain', sum: 35, clientId: 'client_ch', payerEmail: 'ch@x.com',
  };
  const ev = parseWebhook(payload); // REAL parse
  assert.equal(ev.subscriptionId, u); assert.equal(ev.planId, 'monthly');
  assert.equal(ev.amountAgorot, 3500); assert.equal(ev.cardLast4, '1234');
  const r = await en.applyPayment(ev);
  assert.equal(r.activated, true);
  const sub = await s.getSubscription(u);
  assert.equal(sub.status, 'active'); assert.equal(sub.cardLast4, '1234');
  assert.equal(sub.paymentToken, 'tok_real'); assert.equal(sub.cardBrand, 'mastercard');
  const inv = await en.listInvoices(u);
  assert.equal(inv[0].transactionId, 'CHAIN1'); assert.equal(inv[0].morningDocId, 'doc_chain');
  ok('webhook chain: parseWebhook → applyPayment');
}

// ═══════════════════════════════════════════════════════════════════════════
// 28. WEBHOOK CHAIN — nested {data:{…}} envelope + annual amount
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  const u = 'nest'; s.seedProps(u, []);
  clock = Date.parse('2026-09-01T00:00:00Z');
  await en.checkout(u, { plan: 'annual', email: 'ne@x.com', ...urls });
  const ev = parseWebhook({ data: { status: 1, custom: `${u}::annual`, transactionId: 'NEST1', amount: 350, token: 't' } });
  assert.equal(ev.subscriptionId, u); assert.equal(ev.planId, 'annual'); assert.equal(ev.amountAgorot, 35000);
  const r = await en.applyPayment(ev);
  assert.equal(r.activated, true); assert.equal(r.plan, 'annual');
  ok('webhook chain: nested envelope');
}

// ═══════════════════════════════════════════════════════════════════════════
// 29. WEBHOOK CHAIN — duplicate IPN delivery is idempotent end-to-end
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  const u = 'dupchain'; s.seedProps(u, []);
  clock = Date.parse('2026-09-01T00:00:00Z');
  await en.checkout(u, { plan: 'monthly', email: 'dc@x.com', ...urls });
  const ev = parseWebhook({ status: 1, custom: `${u}::monthly`, transactionId: 'DUP1', sum: 35, token: 't' });
  const r1 = await en.applyPayment(ev);
  const r2 = await en.applyPayment(ev); // provider re-delivers the SAME IPN
  assert.equal(r1.activated, true);
  assert.equal(r2.ignored, 'duplicate', 're-delivered IPN is a no-op');
  assert.equal((await en.listInvoices(u)).length, 1, 'exactly one invoice');
  ok('webhook chain: duplicate delivery idempotent');
}

// ═══════════════════════════════════════════════════════════════════════════
// 30. PROPERTY-BASED FUZZ — random op sequences; assert INVARIANTS after each.
//   Deterministic (seeded PRNG) so any failure reproduces from its seed.
//   Safety invariants: no double-billing, monotonic version, sane period,
//   valid status, entitlement matches the domain, downgrade caps active ≤ limit,
//   idempotent IPN re-delivery.
// ═══════════════════════════════════════════════════════════════════════════
{
  const mulberry32 = (seed) => () => {
    let t = (seed += 0x6D2B79F5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const SEEDS = 200; const OPS = 60;
  let totalOps = 0;
  for (let seed = 1; seed <= SEEDS; seed++) {
    const rand = mulberry32(seed);
    const pick = (arr) => arr[Math.floor(rand() * arr.length)];
    const s = makeStore(); const p = makeProvider();
    const en = createEngine({ store: s, provider: p, now });
    clock = Date.parse('2026-09-01T00:00:00Z');
    const u = `fz${seed}`;
    const nProps = Math.floor(rand() * 6); // 0..5
    s.seedProps(u, Array.from({ length: nProps }, (_, i) => ({ id: `p${i}`, createdAt: `2026-01-${String(i + 1).padStart(2, '0')}` })));
    const pastIpns = [];
    let lastPlan = 'monthly';
    let lastVersion = 0;
    let webhookActivations = 0;
    let txc = 0;

    for (let op = 0; op < OPS; op++) {
      totalOps++;
      const action = pick(['checkout', 'pay', 'paydup', 'setfail', 'setok', 'cron', 'cancel', 'resume', 'advance', 'addprop']);
      try {
        if (action === 'checkout') {
          lastPlan = pick(['monthly', 'annual']);
          await en.checkout(u, { plan: lastPlan, email: 'fz@x.com', ...urls });
        } else if (action === 'pay') {
          const amt = lastPlan === 'annual' ? 35000 : 3500;
          const ev = ipn(u, lastPlan, `${u}_${txc++}`, amt);
          const r = await en.applyPayment(ev);
          if (r.activated) { webhookActivations++; pastIpns.push(ev); }
        } else if (action === 'paydup' && pastIpns.length) {
          const ev = pick(pastIpns);
          const invBefore = s._invoices.size;
          const endBefore = (await s.getSubscription(u))?.currentPeriodEnd;
          const r = await en.applyPayment(ev);
          assert.equal(r.ignored, 'duplicate', 're-delivered IPN → duplicate');
          assert.equal(s._invoices.size, invBefore, 'dup IPN → no new invoice');
          assert.equal((await s.getSubscription(u))?.currentPeriodEnd, endBefore, 'dup IPN → period unchanged');
        } else if (action === 'setfail') { p._setCharge({ ok: false }); }
        else if (action === 'setok') { p._setCharge({ ok: true }); }
        else if (action === 'cron') {
          const st = await en.runCron();
          const sub = await s.getSubscription(u);
          if (st.lapsed > 0 && sub?.status === 'canceled') {
            const active = await s.countActiveProperties(u);
            assert.ok(active <= BILLING.FREE_PROPERTY_LIMIT, `downgrade → active(${active}) ≤ ${BILLING.FREE_PROPERTY_LIMIT}`);
          }
        } else if (action === 'cancel') { await en.cancel(u); }
        else if (action === 'resume') { await en.resume(u); }
        else if (action === 'advance') { advanceDays(Math.floor(rand() * 50) + 1); }
        else if (action === 'addprop') {
          const list = s._props.get(u) || [];
          list.push({ id: `np${op}`, createdAt: `2026-08-${String((op % 28) + 1).padStart(2, '0')}`, status: 'active' });
          s._props.set(u, list);
        }

        // ── INVARIANTS (after every op) ──────────────────────────────────────
        const sub = await s.getSubscription(u);
        if (sub) {
          assert.ok(['none', 'active', 'past_due', 'grace', 'canceled'].includes(sub.status), `valid status: ${sub.status}`);
          const v = Number(sub.version) || 0;
          assert.ok(v >= lastVersion, `version monotonic (${v} ≥ ${lastVersion})`); lastVersion = v;
          assert.ok((Number(sub.failedAttempts) || 0) >= 0, 'failedAttempts ≥ 0');
          if (sub.currentPeriodStart && sub.currentPeriodEnd) {
            assert.ok(Date.parse(sub.currentPeriodEnd) > Date.parse(sub.currentPeriodStart), 'period end > start');
          }
          const ent = await en.getEntitlement(u);
          assert.equal(ent.entitled, hasActiveEntitlement(sub, now()), 'entitlement view matches domain');
        }
        // MONEY SAFETY: never more invoices than real payment events (no double-billing).
        assert.ok(s._invoices.size <= webhookActivations + p._realCharges(),
          `no over-billing: invoices(${s._invoices.size}) ≤ webhook(${webhookActivations})+cron(${p._realCharges()})`);
        // every invoice priced at a real plan amount
        for (const inv of s._invoices.values()) {
          assert.ok(inv.sumAgorot === 3500 || inv.sumAgorot === 35000, `invoice sum valid: ${inv.sumAgorot}`);
        }
      } catch (e) {
        console.error(`FUZZ FAIL seed=${seed} op=${op} action=${action}: ${e.message}`);
        throw e;
      }
    }
  }
  ok(`fuzz: ${SEEDS} seeded worlds × ${OPS} ops (${totalOps} steps), all invariants held`);
}

// ═══════════════════════════════════════════════════════════════════════════
// 31. ADVERSARIAL WEBHOOK-PARSE FUZZ — malformed IPNs must never crash or
//     corrupt state (parseWebhook → applyPayment on 500 garbage payloads).
// ═══════════════════════════════════════════════════════════════════════════
{
  const rng = (seed) => () => {
    let t = (seed += 0x6D2B79F5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const rand = rng(777);
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  clock = Date.parse('2026-09-01T00:00:00Z');
  const u = 'wfz'; s.seedProps(u, []);
  await en.checkout(u, { plan: 'monthly', email: 'w@x.com', ...urls });

  const garbage = [null, undefined, '', 0, -1, 999999, 'xxx', {}, [], true, NaN,
    `${u}::monthly`, `${u}::annual`, `${u}::bogus`, u, '::', 'a::b::c', 3500, 35, 350];
  const g = () => garbage[Math.floor(rand() * garbage.length)];
  let crashes = 0;
  for (let i = 0; i < 500; i++) {
    const payload = {
      status: g(), custom: g(), token: g(), cardSuffix: g(), cardBrand: g(),
      transactionId: rand() > 0.3 ? `wtx${i}` : g(), documentId: g(), sum: g(), amount: g(),
      ...(rand() > 0.5 ? { data: { status: g(), custom: g(), transactionId: g(), sum: g() } } : {}),
    };
    let ev;
    try { ev = parseWebhook(payload); } catch (e) { crashes++; console.error('parseWebhook threw:', e.message); continue; }
    assert.ok(ev && typeof ev === 'object', 'parseWebhook returns an object');
    try {
      const r = await en.applyPayment(ev);
      if (r && r.activated) assert.ok(['monthly', 'annual'].includes(r.plan), 'activated → valid plan');
    } catch (e) { crashes++; console.error('applyPayment threw:', e.message); }
  }
  assert.equal(crashes, 0, 'no crash across 500 adversarial IPNs');
  // No garbage ever persisted: every invoice validly priced; every sub sane.
  for (const inv of s._invoices.values()) {
    assert.ok(inv.sumAgorot === 3500 || inv.sumAgorot === 35000, `invoice price valid: ${inv.sumAgorot}`);
  }
  for (const sub of s._subs.values()) {
    assert.ok(['none', 'active', 'past_due', 'grace', 'canceled'].includes(sub.status), `sub status valid: ${sub.status}`);
    if (sub.plan) assert.ok(['monthly', 'annual'].includes(sub.plan), `sub plan valid: ${sub.plan}`);
    if (sub.currentPeriodStart && sub.currentPeriodEnd) {
      assert.ok(Date.parse(sub.currentPeriodEnd) > Date.parse(sub.currentPeriodStart), 'sub period sane');
    }
  }
  ok('webhook-parse fuzz: 500 adversarial payloads, no crash, no corruption');
}

// ═══════════════════════════════════════════════════════════════════════════
// 32. ONE-OFF checkout (50₪ AI-contract unlock) — no subscription activated
// ═══════════════════════════════════════════════════════════════════════════
{
  const s = makeStore(); const p = makeProvider(); const en = createEngine({ store: s, provider: p, now });
  const u = 'oneoff'; s.seedProps(u, []);
  clock = Date.parse('2026-09-01T00:00:00Z');
  // SERVER-authoritative price: unknown/absent product is rejected, and a
  // client-sent amount is IGNORED (anti-tamper — can't pay ₪0.01 for a ₪50 unlock).
  assert.equal((await en.checkoutOneOff(u, {})).error, 'bad_product', 'missing product rejected');
  assert.equal((await en.checkoutOneOff(u, { product: 'nope' })).error, 'bad_product', 'unknown product rejected');
  const r = await en.checkoutOneOff(u, { amountAgorot: 1, product: 'contract', email: 'o@x.com', name: 'דנה', ...urls });
  assert.ok(r.url && r.url.includes('oneoff'), 'one-off returns a checkout url');
  const sub = await s.getSubscription(u);
  assert.ok(sub.morningClientId, 'a Morning client was created/reused');
  assert.equal(sub.status, 'none', 'one-off does NOT activate a subscription');
  const form = p._forms[p._forms.length - 1];
  assert.equal(form.custom, `${u}::oneoff::contract`, 'custom encodes uid::oneoff::product');
  assert.equal(form.amountIls, 50, 'server prices contract at ₪50 (client amountAgorot:1 IGNORED)');
  ok('one-off checkout (server-priced, tamper-proof)');
}

console.log(`subscription_engine.selfcheck: ALL PASS ✓ (${PASS} scenarios)`);
