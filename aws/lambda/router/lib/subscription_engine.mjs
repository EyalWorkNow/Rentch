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
  hasActiveEntitlement, cronAction, dunningAfterFailure, resolveCoupon,
  resolveOneOffProduct, boostState, boostProductMeta, BOOST_DAYS,
} from './billing.mjs';

const iso = (ms) => new Date(ms).toISOString();

// The price actually charged for a subscription: a stored coupon price overrides
// the plan's list price (set once at checkout, preserved by casUpdate's merge).
const effectivePlan = (plan, sub) =>
  sub?.couponPriceAgorot != null
    ? { ...plan, priceAgorot: sub.couponPriceAgorot }
    : plan;
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
  async function checkout(uid, { plan: planId, email, name, coupon, group, successUrl, failureUrl, notifyUrl }) {
    const plan = planById(planId);
    if (!plan) return { error: 'bad_plan' };
    // Resolve the coupon SERVER-SIDE — the discounted price is authoritative and
    // is persisted so the IPN amount-check and later renewals honour it too.
    const promo = resolveCoupon(coupon, plan.id, now());
    const charged = promo ? { ...plan, priceAgorot: promo.priceAgorot } : plan;
    const existing = await store.getSubscription(uid);
    let clientId = existing?.morningClientId || null;
    if (!clientId && (email || name)) {
      clientId = await provider.upsertClient({ name, email });
    }
    await casUpdate(uid, (sub) => ({
      pendingPlan: plan.id,
      couponCode: promo ? promo.code : null,
      couponPriceAgorot: promo ? promo.priceAgorot : null,
      morningClientId: clientId || sub.morningClientId || null,
      ownerUserId: uid,
      ...(sub.status ? {} : { status: BILLING.STATUS.NONE }),
    }));
    const { url } = await provider.createPaymentForm({
      plan: charged, clientId, clientName: name, clientEmail: email,
      subscriptionId: `${uid}::${plan.id}`, // binds the granted plan to the paid link
      group, successUrl, failureUrl, notifyUrl,
    });
    return { url, plan: plan.id, coupon: promo ? promo.code : null, priceAgorot: charged.priceAgorot };
  }

  // ── one-off hosted payment (e.g. the 50₪ AI-contract unlock) ────────────────
  // Not a subscription: returns a checkout URL for a single charge. The feature
  // unlocks on the client when the hosted page returns success (Morning issues
  // the receipt automatically); no webhook/subscription state is touched.
  async function checkoutOneOff(uid, { product, propertyId, description, email, name, group, successUrl, failureUrl, notifyUrl }) {
    // SERVER-authoritative price: look it up from the product, never trust a
    // client-sent amount (which could be ₪0.01 for a paid unlock).
    const prod = resolveOneOffProduct(product);
    if (!prod) return { error: 'bad_product' };
    // A paid boost must name the property it applies to.
    if (boostProductMeta(product) && !propertyId) return { error: 'missing_property' };
    const amountIls = prod.priceAgorot / 100;
    description = description || prod.description;
    const existing = await store.getSubscription(uid);
    let clientId = existing?.morningClientId || null;
    if (!clientId && (email || name)) {
      clientId = await provider.upsertClient({ name, email });
      await casUpdate(uid, (sub) => ({
        morningClientId: clientId || sub.morningClientId || null,
        ownerUserId: uid,
        ...(sub.status ? {} : { status: BILLING.STATUS.NONE }),
      }));
    }
    const { url } = await provider.createPaymentFormOneOff({
      amountIls, description, clientId, clientName: name, clientEmail: email,
      // custom carries uid::oneoff::product::propertyId so the IPN/confirm can
      // apply the paid boost to the right listing.
      custom: `${uid}::oneoff::${product || 'x'}::${propertyId || ''}`,
      group, successUrl, failureUrl, notifyUrl,
    });
    return { url };
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
      // Honour a stored coupon price so a discounted (e.g. ₪1) charge clears the
      // anti-tamper amount-check instead of being rejected as a mismatch.
      const plan = effectivePlan(planById(planId) || BILLING.plans.monthly, sub);
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
      sumAgorot: row.couponPriceAgorot ?? planById(row.plan)?.priceAgorot ?? null,
      transactionId: ev.transactionId || null,
      periodStart: row.currentPeriodStart,
      periodEnd: row.currentPeriodEnd,
      issuedAt: iso(now()),
    });
    return { activated: true, plan: row.plan, periodEnd: row.currentPeriodEnd };
  }

  // ── verify-on-return activation (IPN-independent) ───────────────────────────
  // Called when the user returns from the hosted payment page. Confirms the
  // payment by asking the provider (Morning) for a fresh paid receipt for this
  // client, then activates — so activation never depends on the unverified IPN.
  async function confirm(uid) {
    const sub = await store.getSubscription(uid);
    if (!sub || !sub.morningClientId) return { confirmed: false, reason: 'no_client' };
    // Already entitled (a prior confirm/IPN activated it) → idempotent success.
    if (hasActiveEntitlement(sub, now())) {
      return { confirmed: true, plan: sub.plan, alreadyActive: true };
    }
    let doc = null;
    try {
      doc = await provider.findRecentPaidDocument({
        clientId: sub.morningClientId,
        sinceIso: day(now() - 2 * 24 * 3600 * 1000), // last 48h window
      });
    } catch (e) { log('confirm: document search failed', uid, e?.message); }
    if (!doc) return { confirmed: false, reason: 'no_payment_found' };
    // Grab the saved card token (best-effort) so monthly renewals can charge it.
    let tok = null;
    try { tok = await provider.findCardToken?.({ clientId: sub.morningClientId }); }
    catch (e) { log('confirm: token search failed', uid, e?.message); }
    const res = await applyPayment({
      subscriptionId: uid,
      planId: sub.pendingPlan || sub.plan || 'monthly',
      transactionId: doc.transactionId || doc.docId,
      docId: doc.docId,
      docUrl: doc.docUrl,
      amountAgorot: doc.amountAgorot,
      token: tok?.token || null,
      cardLast4: tok?.cardLast4 || null,
      cardBrand: tok?.cardBrand || null,
      success: true,
    });
    if (res.activated) return { confirmed: true, plan: res.plan, periodEnd: res.periodEnd };
    if (res.ignored === 'duplicate') return { confirmed: true, alreadyActive: true };
    return { confirmed: false, reason: res.ignored || 'not_activated' };
  }

  // ── boost a listing ("הקפצת מודעה") ─────────────────────────────────────────
  // Entitlement-gated + monthly-quota-limited. Stamps boostedUntil + tier on the
  // property (owner-verified in the store) and consumes one regular boost. Ultra
  // is never quota-based — it comes only through the paid one-off path.
  async function boost(uid, propertyId) {
    if (!propertyId) return { error: 'bad_request' };
    const sub = await store.getSubscription(uid);
    if (!hasActiveEntitlement(sub, now())) return { error: 'not_entitled' };
    const st = boostState(sub, now());
    if (st.remaining !== Infinity && st.remaining <= 0) {
      return { error: 'quota_exceeded', quota: st.quota, used: st.used };
    }
    const until = new Date(now() + st.days * 24 * 3600 * 1000).toISOString();
    const ok = await store.boostProperty(propertyId, uid, until, 'regular');
    if (!ok) return { error: 'not_owner' }; // property missing or not this user's
    await casUpdate(uid, (s) => {
      const month = new Date(now()).toISOString().slice(0, 7);
      const used = s.boostMonth === month ? (s.boostsUsed || 0) : 0;
      return { boostMonth: month, boostsUsed: used + 1 };
    });
    const after = boostState(await store.getSubscription(uid), now());
    return {
      ok: true,
      boostedUntil: until,
      tier: 'regular',
      remaining: after.remaining === Infinity ? null : after.remaining,
      unlimited: st.quota === Infinity,
    };
  }

  // ── apply a PAID one-off boost (₪10 regular / ₪50 ultra) ─────────────────────
  // Stamps the property with the purchased tier once the payment is verified.
  // Idempotent via the invoice table. Amount-checked against the product price so
  // a crafted low charge can't unlock a boost.
  async function applyOneOffBoost(ev) {
    const { uid, product, propertyId } = ev;
    const meta = boostProductMeta(product);
    if (!meta) return { ignored: 'not_a_boost' };
    if (!uid || !propertyId) return { ignored: 'missing_target' };
    if (ev.success === false) return { ignored: 'not_successful' };
    if (ev.amountAgorot != null && ev.amountAgorot !== meta.priceAgorot) {
      return { ignored: 'amount_mismatch', expected: meta.priceAgorot, got: ev.amountAgorot };
    }
    const invoiceId = String(ev.transactionId || ev.docId || `${uid}:boost:${propertyId}:${product}`);
    if (await store.hasInvoice(invoiceId)) return { ignored: 'duplicate', boostedUntil: ev.boostedUntil || null };
    const until = new Date(now() + (meta.boostDays || BOOST_DAYS) * 24 * 3600 * 1000).toISOString();
    const ok = await store.boostProperty(propertyId, uid, until, meta.tier);
    if (!ok) return { ignored: 'not_owner' };
    await store.putInvoice({
      id: invoiceId, ownerUserId: uid, plan: `boost_${meta.tier}`,
      morningDocId: ev.docId || null, url: ev.docUrl || null,
      sumAgorot: meta.priceAgorot, transactionId: ev.transactionId || null,
      issuedAt: iso(now()),
    });
    return { applied: true, boostedUntil: until, tier: meta.tier };
  }

  // Verify-on-return for a paid boost: the client returns from the hosted page,
  // we confirm a matching paid receipt with Morning, then stamp the boost.
  async function confirmOneOff(uid, { product, propertyId }) {
    const meta = boostProductMeta(product);
    if (!meta) return { ok: false, reason: 'not_a_boost' };
    if (!propertyId) return { ok: false, reason: 'missing_property' };
    const sub = await store.getSubscription(uid);
    if (!sub || !sub.morningClientId) return { ok: false, reason: 'no_client' };
    let doc = null;
    try {
      doc = await provider.findRecentPaidDocument({
        clientId: sub.morningClientId,
        sinceIso: day(now() - 2 * 24 * 3600 * 1000),
        amountAgorot: meta.priceAgorot, // amount-aware match
      });
    } catch (e) { log('confirmOneOff: document search failed', uid, e?.message); }
    if (!doc) return { ok: false, reason: 'no_payment_found' };
    const res = await applyOneOffBoost({
      uid, product, propertyId,
      transactionId: doc.transactionId || doc.docId, docId: doc.docId, docUrl: doc.docUrl,
      amountAgorot: doc.amountAgorot, success: true,
    });
    if (res.applied) return { ok: true, boostedUntil: res.boostedUntil, tier: res.tier };
    if (res.ignored === 'duplicate') return { ok: true, boostedUntil: res.boostedUntil, tier: meta.tier, alreadyApplied: true };
    return { ok: false, reason: res.ignored || 'not_applied' };
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
    const plan = effectivePlan(planById(sub.plan) || BILLING.plans.monthly, sub);
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
    getEntitlement, enforceQuota, checkout, checkoutOneOff, applyPayment, confirm,
    confirmOneOff, applyOneOffBoost, boost, cancel, resume, listInvoices, runCron, grandfather,
    // exposed for targeted use/testing:
    _casUpdate: casUpdate, _chargeOne: chargeOne, _lapse: lapse,
  };
}
