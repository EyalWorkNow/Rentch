// Billing domain logic — the single source of truth for the landlord
// subscription paywall. Pure functions only (no AWS/HTTP) so it's trivially
// unit-testable; the router wires these to DynamoDB + Morning/Grow.
//
// Locked product decisions (2026-07-23):
//  · Prices are VAT-INCLUSIVE (18%). Morning splits the VAT on the document.
//  · Free tier = up to 3 ACTIVE properties. The 4th requires an entitlement.
//  · Downgrade PAUSES properties beyond 3 (never deletes).
//  · Pre-existing owners with >3 properties get a 30-day grandfather grace.

export const BILLING = {
  // A landlord may keep this many ACTIVE properties for free. Publishing one
  // that would exceed this needs an active entitlement.
  FREE_PROPERTY_LIMIT: 3,

  // Israeli VAT — informational; Morning computes the split on the invoice.
  VAT_RATE: 0.18,

  // Prices in agorot (₪1 = 100 agorot), VAT-inclusive.
  plans: {
    monthly: { id: 'monthly', priceAgorot: 3500,  months: 1,  label: 'חודשי' },
    annual:  { id: 'annual',  priceAgorot: 35000, months: 12, label: 'שנתי'  },
  },

  // Grandfather window for owners who already hold >3 properties at launch.
  GRACE_DAYS_EXISTING: 30,

  // Failed-charge dunning: retry on these day-offsets, then past_due.
  DUNNING_RETRY_DAYS: [1, 3, 5],
  // After the final failed retry, keep the entitlement alive this many days
  // (a soft "your payment failed, fix it" window) before downgrading.
  PAST_DUE_GRACE_DAYS: 7,

  // Statuses a subscription row can hold.
  STATUS: {
    NONE: 'none',
    ACTIVE: 'active',
    PAST_DUE: 'past_due',
    GRACE: 'grace',
    CANCELED: 'canceled',
  },
};

export function planById(id) {
  return BILLING.plans[id] || null;
}

// Add N calendar months to a millisecond timestamp, returned as an ISO string.
// Uses setMonth so it tracks real month lengths (Jan 31 + 1mo → Feb 28/29).
export function addMonths(fromMs, months) {
  const d = new Date(fromMs);
  const targetDay = d.getDate();
  d.setMonth(d.getMonth() + months);
  // Guard month overflow (e.g. Mar 31 + 1 → May 1): clamp back to month end.
  if (d.getDate() < targetDay) d.setDate(0);
  return d.toISOString();
}

// Parse an ISO/epoch value to ms, or null.
function ms(v) {
  if (v == null) return null;
  if (typeof v === 'number') return v;
  const t = Date.parse(v);
  return Number.isNaN(t) ? null : t;
}

// Is this subscription row currently ENTITLED to exceed the free limit?
// `now` is a ms timestamp (injected so this stays pure & testable).
export function hasActiveEntitlement(sub, now) {
  if (!sub) return false;
  const S = BILLING.STATUS;
  const end = ms(sub.currentPeriodEnd);
  const grace = ms(sub.graceUntil);
  const grandfather = ms(sub.grandfatherUntil);

  // A paid, in-period subscription.
  if (sub.status === S.ACTIVE) {
    return end == null || end > now;
  }
  // Payment failed but still inside the soft grace window.
  if (sub.status === S.PAST_DUE || sub.status === S.GRACE) {
    return grace != null && grace > now;
  }
  // Launch grandfather window for pre-existing >3 owners (independent of status).
  if (grandfather != null && grandfather > now) return true;
  return false;
}

// The client-facing entitlement snapshot: everything the app needs to render
// the paywall / "my subscription" screen and to gate the add-property button.
export function entitlementView(sub, activeCount, now) {
  const entitled = hasActiveEntitlement(sub, now);
  const limit = BILLING.FREE_PROPERTY_LIMIT;
  return {
    status: sub?.status || BILLING.STATUS.NONE,
    plan: sub?.plan || null,
    priceAgorot: sub ? (planById(sub.plan)?.priceAgorot ?? null) : null,
    currentPeriodEnd: sub?.currentPeriodEnd || null,
    cancelAtPeriodEnd: !!sub?.cancelAtPeriodEnd,
    card: sub && (sub.cardLast4 || sub.cardBrand)
      ? { brand: sub.cardBrand || null, last4: sub.cardLast4 || null }
      : null,
    activeProperties: activeCount,
    freeLimit: limit,
    entitled,
    // The single boolean the client gates the "add property" button on.
    canAddProperty: entitled || activeCount < limit,
    graceUntil: sub?.graceUntil || null,
    grandfatherUntil: sub?.grandfatherUntil || null,
  };
}

// Compute the new billing period after a successful charge. Early renewals
// STACK: the period extends from the later of `now` or the current period end,
// so paying again before expiry never loses paid-for days. `now` is ms.
export function nextPeriod(sub, plan, now) {
  const currentEnd = sub?.currentPeriodEnd ? Date.parse(sub.currentPeriodEnd) : NaN;
  const base = Number.isFinite(currentEnd) && currentEnd > now ? currentEnd : now;
  return {
    periodStart: new Date(now).toISOString(),
    periodEnd: addMonths(base, plan.months),
  };
}

// The subscription-row patch to apply after a SUCCESSFUL charge (first payment
// or renewal). Pure; recompute-safe (call it with the freshest `sub` inside an
// optimistic-locking retry so early-renewal stacking stays correct). `charge`
// optionally carries token/card/txn details (present on a first payment IPN,
// absent on a token renewal → the stored values are preserved).
export function renewedRow(sub, plan, now, charge = {}) {
  const { periodStart, periodEnd } = nextPeriod(sub, plan, now);
  return {
    status: BILLING.STATUS.ACTIVE,
    plan: plan.id,
    pendingPlan: null,
    currentPeriodStart: periodStart,
    currentPeriodEnd: periodEnd,
    cancelAtPeriodEnd: false,
    lastPaymentAt: periodStart,
    lastTransactionId: charge.transactionId || sub.lastTransactionId || null,
    paymentToken: charge.token || sub.paymentToken || null,
    cardLast4: charge.cardLast4 || sub.cardLast4 || null,
    cardBrand: charge.cardBrand || sub.cardBrand || null,
    morningClientId: charge.clientId || sub.morningClientId || null,
    failedAttempts: 0,
    nextRetryAt: null,
    graceUntil: null,
  };
}

// ── nightly cron scheduling (pure) ───────────────────────────────────────────

// Decide what the nightly billing cron should do with one subscription at `now`
// (ms). Pure — the cron performs the side effects (charge / downgrade).
//   { action: 'noop' }                       nothing due
//   { action: 'charge', reason: 'renewal' }  active period ended → renew
//   { action: 'charge', reason: 'retry' }    a dunning retry is due
//   { action: 'lapse' }                       grace over / canceled at period end → downgrade
export function cronAction(sub, now) {
  const S = BILLING.STATUS;
  if (!sub) return { action: 'noop' };
  const end = sub.currentPeriodEnd ? Date.parse(sub.currentPeriodEnd) : null;
  const grace = sub.graceUntil ? Date.parse(sub.graceUntil) : null;
  const retryAt = sub.nextRetryAt ? Date.parse(sub.nextRetryAt) : null;

  if (sub.status === S.ACTIVE) {
    if (sub.cancelAtPeriodEnd) {
      return (end != null && end <= now) ? { action: 'lapse' } : { action: 'noop' };
    }
    if (end != null && end <= now) return { action: 'charge', reason: 'renewal' };
    return { action: 'noop' };
  }
  if (sub.status === S.PAST_DUE || sub.status === S.GRACE) {
    if (grace != null && grace <= now) return { action: 'lapse' };     // grace expired → downgrade
    if (retryAt != null && retryAt <= now) return { action: 'charge', reason: 'retry' };
    return { action: 'noop' };
  }
  return { action: 'noop' }; // canceled / none → nothing to bill
}

// After a FAILED charge, advance the dunning state. Returns the patch to apply.
// Entitlement is kept alive during dunning via graceUntil (set once, on the
// first failure) so a transient decline doesn't instantly lock the landlord out.
export function dunningAfterFailure(sub, now) {
  const attempts = (Number(sub.failedAttempts) || 0) + 1;
  const schedule = BILLING.DUNNING_RETRY_DAYS; // e.g. [1,3,5] day gaps between retries
  const totalGraceDays = schedule.reduce((a, b) => a + b, 0) + BILLING.PAST_DUE_GRACE_DAYS;
  const graceUntil = sub.graceUntil || new Date(now + totalGraceDays * 864e5).toISOString();
  const nextRetryAt = attempts <= schedule.length
    ? new Date(now + schedule[attempts - 1] * 864e5).toISOString()
    : null; // retries exhausted → ride out the remaining grace, then lapse
  return { status: BILLING.STATUS.PAST_DUE, failedAttempts: attempts, nextRetryAt, graceUntil };
}

// Would publishing ONE more active property require an entitlement the owner
// doesn't have? `activeCount` is their CURRENT active-property count.
// Returns null when allowed, or a machine-readable reason object when blocked.
export function quotaBlockReason(sub, activeCount, now) {
  if (activeCount < BILLING.FREE_PROPERTY_LIMIT) return null; // still inside free tier
  if (hasActiveEntitlement(sub, now)) return null;            // paid / grace / grandfather
  return {
    error: 'subscription_required',
    code: 'PROP_LIMIT',
    activeProperties: activeCount,
    freeLimit: BILLING.FREE_PROPERTY_LIMIT,
  };
}
