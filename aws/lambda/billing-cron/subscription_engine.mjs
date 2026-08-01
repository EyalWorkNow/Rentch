// Subscription engine — the SINGLE source of truth for the whole landlord
// subscription lifecycle. Pure orchestration: all I/O is injected as `store`
// (persistence) + `provider` (Morning/Grow) + `now` (clock), so the entire
// end-to-end flow is unit-testable with in-memory fakes, and the router and the
// cron share ONE implementation (no drift).
//
//   const engine = createEngine({ store, provider, now });
//   engine.getEntitlement(uid) / enforceQuota(uid) / checkout(uid,opts) /
//   applyPayment(ev) / cancel(uid) / resume(uid) / listInvoices(uid) /
//   runCron() / grandfather(days)
//
// store contract (all async):
//   getSubscription(uid) -> row|null
//   casPutSubscription(uid, expectedVersion, row) -> bool   (optimistic lock)
//   putInvoice(item) -> bool                                (idempotent by id)
//   hasInvoice(id) -> bool                                  (durable idempotency ledger)
//   listInvoices(uid) -> [item]
//   countActiveProperties(uid) -> number (>=0) or -1 on error (fail-open)
//   listActivePropertiesOldestFirst(uid) -> [{id, createdAt}]
//   pauseProperty(id, atISO) -> void
//   scanSubscriptions() -> async iterable of rows
//   ownerActiveCounts() -> Map(uid -> activeCount)          (grandfather only)
//
// provider contract (all async):
//   upsertClient({name,email}) -> clientId
//   createPaymentForm({plan,clientId,clientName,clientEmail,subscriptionId,successUrl,failureUrl,notifyUrl}) -> {url}
//   chargeToken({plan,token,clientId,idempotencyKey}) -> {ok,transactionId,docId,docUrl}

import {
  BILLING, planById, renewedRow, entitlementView, quotaBlockReason,
  hasActiveEntitlement, cronAction, dunningAfterFailure,
} from './billing.mjs';

const iso = (ms) => new Date(ms).toISOString();
const day = (ms) => iso(ms).slice(0, 10);

export function createEngine({ store, provider, now = () => Date.now(), log = () => {} }) {
  // Optimistic-concurrency update: buildPatch(sub) runs on the FRESHEST row each
  // attempt (so period stacking recomputes on conflict). Return null to abort.
  async function casUpdate(uid, buildPatch, tries = 5) {
    for (let i = 0; i < tries; i++) {
      const sub = (await store.getSubscription(uid)) || { id: uid, version: 0 };
      const patch = buildPatch(sub);
      if (patch === null) return null;
      const version = Number(sub.version) || 0;
      const row = { ...sub, ...patch, id: uid, version: version + 1, updatedAt: iso(now()) };
      if (await store.casPutSubscription(uid, version, row)) return row;
    }
    return null; // exhausted retries
  }

  // ── entitlement / gate ─────────────────────────────────────────────────────
  async function getEntitlement(uid) {
    const [sub, rawCount] = await Promise.all([
      store.getSubscription(uid),
      store.countActiveProperties(uid),
    ]);
    const count = rawCount < 0 ? 0 : rawCount;
    return entitlementView(sub, count, now());
  }

  // Returns a 402-style block object, or null to allow the publish. Fail-open on
  // an unknown count (the paywall is a monetization gate, not security; the cron
  // reconciles). Enforcement is also flag-gated by the caller (BILLING_ENFORCE).
  async function enforceQuota(uid) {
    if (!uid) return null;
    const count = await store.countActiveProperties(uid);
    if (count < 0) return null;
    if (count < BILLING.FREE_PROPERTY_LIMIT) return null;
    const sub = await store.getSubscription(uid);
    return quotaBlockReason(sub, count, now());
  }

  // ── checkout ───────────────────────────────────────────────────────────────
  async function checkout(uid, { plan: planId, email, name, successUrl, failureUrl, notifyUrl }) {
    const plan = planById(planId);
    if (!plan) return { error: 'bad_plan' };
    const existing = await store.getSubscription(uid);
    let clientId = existing?.morningClientId || null;
    if (!clientId && (email || name)) {
      clientId = await provider.upsertClient({ name, email });
    }
    await casUpdate(uid, (sub) => ({
      pendingPlan: plan.id,
      morningClientId: clientId || sub.morningClientId || null,
      ownerUserId: uid,
      ...(sub.status ? {} : { status: BILLING.STATUS.NONE }),
    }));
    const { url } = await provider.createPaymentForm({
      plan, clientId, clientName: name, clientEmail: email,
      subscriptionId: `${uid}::${plan.id}`, // binds the granted plan to the paid link
      successUrl, failureUrl, notifyUrl,
    });
    return { url, plan: plan.id };
  }

  // ── activation from a verified payment event (webhook OR cron renewal) ──────
  // Idempotent (duplicate transaction = no-op), amount-cross-checked, version-
  // guarded with period-stacking recompute. `ev` = parsed+verified payment:
  //   { subscriptionId(uid), planId?, transactionId, docId?, docUrl?, token?,
  //     cardLast4?, cardBrand?, clientId?, amountAgorot?, success }
  async function applyPayment(ev) {
    const uid = ev.subscriptionId;
    if (!uid) return { ignored: 'no_subscription_id' };
    if (ev.success === false) return { ignored: 'not_successful' };
    // DURABLE idempotency: the invoice table records EVERY processed transaction,
    // so re-delivery of ANY past IPN (not only the most recent) is a no-op. The
    // lastTransactionId check inside casUpdate is just the fast path.
    const priorId = String(ev.transactionId || ev.docId || '');
    if (priorId && (await store.hasInvoice(priorId))) return { ignored: 'duplicate' };
    let outcome = null;
    const row = await casUpdate(uid, (sub) => {
      if (ev.transactionId && sub.lastTransactionId === ev.transactionId) {
        outcome = { ignored: 'duplicate' };
        return null;
      }
      const planId = ev.planId || sub.pendingPlan || sub.plan || 'monthly';
      const plan = planById(planId) || BILLING.plans.monthly;
      if (ev.amountAgorot != null && ev.amountAgorot !== plan.priceAgorot) {
        outcome = { ignored: 'amount_mismatch', expected: plan.priceAgorot, got: ev.amountAgorot };
        log('applyPayment amount mismatch', uid, outcome);
        return null;
      }
      return { ...renewedRow(sub, plan, now(), ev), ownerUserId: uid };
    });
    if (!row) return outcome || { ignored: 'no_write' };
    await store.putInvoice({
      id: String(ev.transactionId || ev.docId || `${uid}:${row.currentPeriodStart}`),
      ownerUserId: uid,
      plan: row.plan,
      morningDocId: ev.docId || null,
      url: ev.docUrl || null,
      sumAgorot: planById(row.plan)?.priceAgorot ?? null,
      transactionId: ev.transactionId || null,
      periodStart: row.currentPeriodStart,
      periodEnd: row.currentPeriodEnd,
      issuedAt: iso(now()),
    });
    return { activated: true, plan: row.plan, periodEnd: row.currentPeriodEnd };
  }

  // ── cancel / resume ─────────────────────────────────────────────────────────
  async function cancel(uid) {
    const sub = await store.getSubscription(uid);
    if (!sub || sub.status === BILLING.STATUS.NONE) return { error: 'no_subscription' };
    const row = await casUpdate(uid, () => ({ cancelAtPeriodEnd: true }));
    return { ok: true, row };
  }
  async function resume(uid) {
    const sub = await store.getSubscription(uid);
    if (!sub) return { error: 'no_subscription' };
    const row = await casUpdate(uid, () => ({ cancelAtPeriodEnd: false }));
    return { ok: true, row };
  }
  async function listInvoices(uid) { return store.listInvoices(uid); }

  // ── cron: renewal / dunning / lapse ─────────────────────────────────────────
  async function chargeOne(sub) {
    const uid = sub.id;
    const today = day(now());
    const plan = planById(sub.plan) || BILLING.plans.monthly;
    if (!sub.paymentToken) {
      await casUpdate(uid, (s) => dunningAfterFailure(s, now()));
      return false;
    }
    // ATOMIC pre-mark: the conditional write IS the once-per-day gate.
    const marked = await casUpdate(uid, (s) => (s.lastChargeDate === today ? null : { lastChargeDate: today }));
    if (!marked) return true; // already attempted today (retry-safe / concurrent run)

    const idempotencyKey = `${uid}:${sub.currentPeriodEnd || 'init'}`;
    let res;
    try {
      res = await provider.chargeToken({ plan, token: sub.paymentToken, clientId: sub.morningClientId, idempotencyKey });
    } catch (e) { log('chargeToken threw', uid, e?.message); res = { ok: false }; }

    if (res.ok) {
      let ps = null; let pe = null;
      await casUpdate(uid, (s) => {
        const p = renewedRow(s, plan, now(), { transactionId: res.transactionId });
        ps = p.currentPeriodStart; pe = p.currentPeriodEnd;
        return p; // lastChargeDate stays today
      });
      await store.putInvoice({
        id: String(res.transactionId || res.docId || `${uid}:${sub.currentPeriodEnd || today}`),
        ownerUserId: uid, plan: plan.id, morningDocId: res.docId || null, url: res.docUrl || null,
        sumAgorot: plan.priceAgorot, transactionId: res.transactionId || null,
        periodStart: ps, periodEnd: pe, issuedAt: iso(now()),
      });
      return true;
    }
    await casUpdate(uid, (s) => dunningAfterFailure(s, now()));
    return false;
  }

  async function lapse(sub) {
    const uid = sub.id;
    // Pause active properties beyond the free limit, NEWEST first (keep oldest).
    const items = await store.listActivePropertiesOldestFirst(uid);
    const toPause = items.slice(BILLING.FREE_PROPERTY_LIMIT);
    for (const it of toPause) await store.pauseProperty(it.id, iso(now()));
    await casUpdate(uid, () => ({
      status: BILLING.STATUS.CANCELED,
      canceledAt: iso(now()),
      lastPausedCount: toPause.length,
      nextRetryAt: null,
    }));
    return toPause.length;
  }

  async function runCron() {
    const stats = { processed: 0, charged: 0, failed: 0, lapsed: 0, noop: 0, errors: 0 };
    for await (const sub of store.scanSubscriptions()) {
      stats.processed++;
      try {
        const act = cronAction(sub, now());
        if (act.action === 'charge') { (await chargeOne(sub)) ? stats.charged++ : stats.failed++; }
        else if (act.action === 'lapse') { await lapse(sub); stats.lapsed++; }
        else stats.noop++;
      } catch (e) { stats.errors++; log('cron sub error', sub?.id, e?.message); }
    }
    return stats;
  }

  // ── grandfather rollout (one-time) ──────────────────────────────────────────
  async function grandfather(days) {
    const until = iso(now() + (Number(days) || BILLING.GRACE_DAYS_EXISTING) * 864e5);
    const counts = await store.ownerActiveCounts();
    let stamped = 0;
    for (const [uid, count] of counts) {
      if (count <= BILLING.FREE_PROPERTY_LIMIT) continue;
      const sub = await store.getSubscription(uid);
      if (sub && (sub.status === BILLING.STATUS.ACTIVE || sub.grandfatherUntil)) continue;
      await casUpdate(uid, (s) => ({
        status: (s.status && s.status !== BILLING.STATUS.NONE) ? s.status : BILLING.STATUS.NONE,
        ownerUserId: uid,
        grandfatherUntil: until,
      }));
      stamped++;
    }
    return { owners: counts.size, stamped, until };
  }

  return {
    getEntitlement, enforceQuota, checkout, applyPayment,
    cancel, resume, listInvoices, runCron, grandfather,
    // exposed for targeted use/testing:
    _casUpdate: casUpdate, _chargeOne: chargeOne, _lapse: lapse,
  };
}
