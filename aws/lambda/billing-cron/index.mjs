// Rently billing cron — scheduled (EventBridge, daily) Lambda. A thin wrapper
// over the SHARED, unit-tested subscription engine: renews due subscriptions,
// runs dunning on failed charges, and downgrades lapsed landlords by PAUSING
// their properties beyond the free limit (never deleting).
//
// billing.mjs + morning.mjs + subscription_engine.mjs + ddb_store.mjs are COPIED
// in from ../router/lib at build time (aws/build-billing-cron.sh) so the domain
// logic has a single source of truth.
//
// Env: TABLE_PREFIX, MORNING_* (for chargeToken on renewals).
// Manual grandfather run:
//   aws lambda invoke --function-name <fn> --payload '{"mode":"grandfather","days":30}' out.json

import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { createEngine } from './subscription_engine.mjs';
import { createDdbStore } from './ddb_store.mjs';
import * as morning from './morning.mjs';

const REGION = process.env.AWS_REGION;
const PREFIX = process.env.TABLE_PREFIX || 'rentch-';

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }), {
  marshallOptions: { removeUndefinedValues: true },
});

const store = createDdbStore({
  ddb,
  tables: {
    subscriptions: `${PREFIX}subscriptions`,
    invoices: `${PREFIX}invoices`,
    invoicesOwnerIndex: 'ownerUserId-issuedAt',
    properties: `${PREFIX}properties`,
    propertiesOwnerIndex: 'ownerUserId-createdAt',
  },
});
const provider = {
  upsertClient: (o) => morning.upsertClient(o),
  createPaymentForm: (o) => morning.createPaymentForm(o),
  chargeToken: (o) => morning.chargeToken(o),
};
const engine = createEngine({ store, provider, now: () => Date.now(), log: (...a) => console.error('cron:', ...a) });

export const handler = async (event = {}) => {
  if (event && event.mode === 'grandfather') {
    const r = await engine.grandfather(event.days);
    console.log('billing-cron grandfather:', JSON.stringify(r));
    return r;
  }
  const stats = await engine.runCron();
  console.log('billing-cron done:', JSON.stringify(stats));
  return stats;
};
