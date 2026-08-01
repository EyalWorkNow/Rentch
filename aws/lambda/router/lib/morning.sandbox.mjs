// LIVE smoke test against the Morning / Green Invoice SANDBOX — no mocks, no
// AWS, no deploy. Validates that morning.mjs's real endpoints/fields work
// against the actual sandbox, so we finalise the CONFIRM items before prod.
//
// Requires SANDBOX credentials in env (generate at sandbox.d.greeninvoice.co.il):
//   MORNING_API_BASE=https://sandbox.d.greeninvoice.co.il/api/v1
//   MORNING_API_KEY=<sandbox id>
//   MORNING_API_SECRET=<sandbox secret>
//   MORNING_PLUGIN_ID=<sandbox grow terminal id>   (optional for the form step)
//
// Run:
//   cd aws/lambda/router
//   MORNING_API_BASE=https://sandbox.d.greeninvoice.co.il/api/v1 \
//   MORNING_API_KEY=... MORNING_API_SECRET=... MORNING_PLUGIN_ID=... \
//   node lib/morning.sandbox.mjs
import { getToken, upsertClient, createPaymentForm } from './morning.mjs';
import { BILLING } from './billing.mjs';

const plan = BILLING.plans.monthly;
const line = (n, s) => console.log(`\n[${n}] ${s}`);

function need(k) {
  if (!process.env[k]) { console.error(`MISSING env ${k} — see the header of this file.`); process.exit(2); }
}
need('MORNING_API_BASE'); need('MORNING_API_KEY'); need('MORNING_API_SECRET');
if (!/sandbox/i.test(process.env.MORNING_API_BASE)) {
  console.error('REFUSING TO RUN: MORNING_API_BASE is not a sandbox URL. This test must hit sandbox only.');
  process.exit(2);
}

(async () => {
  console.log('Morning SANDBOX smoke test — base:', process.env.MORNING_API_BASE);

  line(1, 'getToken (POST /account/token)…');
  const token = await getToken();
  console.log('    ✓ token received, length', token.length);

  line(2, 'upsertClient (find-or-create a client)…');
  let clientId = null;
  try {
    clientId = await upsertClient({ name: 'Rently Sandbox Test', email: 'sandbox@rently.test' });
    console.log('    ✓ clientId:', clientId);
  } catch (e) {
    console.log('    ✗ upsertClient:', e.status, e.message, JSON.stringify(e.data || {}));
    console.log('    (continuing — createPaymentForm can create the client inline)');
  }

  line(3, 'createPaymentForm (hosted payment page + save token)…');
  try {
    const { url, raw } = await createPaymentForm({
      plan,
      clientId,
      clientName: 'Rently Sandbox Test',
      clientEmail: 'sandbox@rently.test',
      subscriptionId: 'sandbox-uid::monthly',
      successUrl: 'https://example.com/hooks/return?status=success',
      failureUrl: 'https://example.com/hooks/return?status=failure',
      notifyUrl: 'https://example.com/hooks/morning',
    });
    console.log('    ✓ PAYMENT URL:', url);
    console.log('    raw response:', JSON.stringify(raw));
    console.log('\nRESULT: sandbox integration WORKS. Open the URL to pay a test card; the IPN would hit /hooks/morning.');
  } catch (e) {
    console.log('    ✗ createPaymentForm:', e.status, e.message);
    console.log('    server said:', JSON.stringify(e.data || {}, null, 2));
    console.log('\nRESULT: the payment-form field names need adjusting to match the sandbox response above.');
    console.log('This is exactly the CONFIRM step — I will map the fields to what the sandbox expects and re-run.');
    process.exit(1);
  }
})().catch((e) => { console.error('\nFATAL:', e.message); process.exit(1); });
