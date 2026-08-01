// DynamoDB-backed `store` for the subscription engine. Shared by the router and
// the cron so there's ONE persistence implementation. Thin glue (the tested
// logic lives in subscription_engine.mjs); imports the SDK the Lambda runtime
// bundles, so it loads only in-Lambda (not in the local pure-logic self-checks).
import { GetCommand, PutCommand, UpdateCommand, QueryCommand, ScanCommand } from '@aws-sdk/lib-dynamodb';

// tables = { subscriptions, invoices, invoicesOwnerIndex, properties, propertiesOwnerIndex }
export function createDdbStore({ ddb, tables }) {
  const T = tables;

  async function propsQuery(uid, { select, projection } = {}) {
    const items = [];
    let count = 0;
    let ESK;
    do {
      const out = await ddb.send(new QueryCommand({
        TableName: T.properties,
        IndexName: T.propertiesOwnerIndex,
        KeyConditionExpression: '#o = :o',
        FilterExpression: 'attribute_not_exists(#s) OR (#s <> :removed AND #s <> :paused)',
        ExpressionAttributeNames: { '#o': 'ownerUserId', '#s': 'status' },
        ExpressionAttributeValues: { ':o': String(uid), ':removed': 'removed', ':paused': 'paused' },
        ...(select ? { Select: select } : {}),
        ...(projection ? { ProjectionExpression: projection } : {}),
        ScanIndexForward: true, // oldest first
        ExclusiveStartKey: ESK,
      }));
      count += out.Count || 0;
      if (out.Items) items.push(...out.Items);
      ESK = out.LastEvaluatedKey;
    } while (ESK);
    return { items, count };
  }

  return {
    async getSubscription(uid) {
      if (!uid) return null;
      try {
        const r = await ddb.send(new GetCommand({ TableName: T.subscriptions, Key: { id: uid } }));
        return r.Item || null;
      } catch (e) { console.error('store.getSubscription:', e?.message || e); return null; }
    },

    async casPutSubscription(uid, expectedVersion, row) {
      try {
        await ddb.send(new PutCommand({
          TableName: T.subscriptions,
          Item: row,
          ConditionExpression: 'attribute_not_exists(id) OR #v = :v',
          ExpressionAttributeNames: { '#v': 'version' },
          ExpressionAttributeValues: { ':v': expectedVersion },
        }));
        return true;
      } catch (e) {
        if (e?.name === 'ConditionalCheckFailedException') return false;
        throw e;
      }
    },

    async putInvoice(item) {
      try {
        await ddb.send(new PutCommand({
          TableName: T.invoices, Item: item, ConditionExpression: 'attribute_not_exists(id)',
        }));
        return true;
      } catch (e) {
        if (e?.name === 'ConditionalCheckFailedException') return false;
        throw e;
      }
    },

    async hasInvoice(id) {
      if (!id) return false;
      try {
        const r = await ddb.send(new GetCommand({ TableName: T.invoices, Key: { id: String(id) } }));
        return !!r.Item;
      } catch (e) { console.error('store.hasInvoice:', e?.message || e); return false; }
    },

    async listInvoices(uid) {
      try {
        const out = await ddb.send(new QueryCommand({
          TableName: T.invoices,
          IndexName: T.invoicesOwnerIndex,
          KeyConditionExpression: '#o = :o',
          ExpressionAttributeNames: { '#o': 'ownerUserId' },
          ExpressionAttributeValues: { ':o': String(uid) },
          ScanIndexForward: false, // newest first
          Limit: 50,
        }));
        return out.Items || [];
      } catch (e) { console.error('store.listInvoices:', e?.message || e); return []; }
    },

    // Fail-open sentinel: -1 on error (the engine treats <0 as "allow").
    async countActiveProperties(uid) {
      if (!uid) return 0;
      try { return (await propsQuery(uid, { select: 'COUNT' })).count; }
      catch (e) { console.error('store.countActiveProperties:', e?.message || e); return -1; }
    },

    async listActivePropertiesOldestFirst(uid) {
      return (await propsQuery(uid, { projection: 'id, createdAt' })).items;
    },

    async pauseProperty(id, at) {
      await ddb.send(new UpdateCommand({
        TableName: T.properties, Key: { id },
        UpdateExpression: 'SET #s = :paused, pausedByBilling = :t',
        ExpressionAttributeNames: { '#s': 'status' },
        ExpressionAttributeValues: { ':paused': 'paused', ':t': at },
      }));
    },

    // Stamp boostedUntil on a property — ONLY if it belongs to `ownerUserId`
    // (the conditional write is the ownership check). Returns false if the
    // property is missing or not the caller's.
    async boostProperty(id, ownerUserId, untilIso, tier = 'regular') {
      try {
        await ddb.send(new UpdateCommand({
          TableName: T.properties, Key: { id },
          UpdateExpression: 'SET boostedUntil = :u, boostTier = :tier',
          ConditionExpression: '#o = :owner',
          ExpressionAttributeNames: { '#o': 'ownerUserId' },
          ExpressionAttributeValues: { ':u': untilIso, ':owner': ownerUserId, ':tier': tier },
        }));
        return true;
      } catch (e) {
        if (e.name === 'ConditionalCheckFailedException') return false;
        throw e;
      }
    },

    async *scanSubscriptions() {
      let ESK;
      do {
        const out = await ddb.send(new ScanCommand({ TableName: T.subscriptions, ExclusiveStartKey: ESK }));
        for (const it of (out.Items || [])) yield it;
        ESK = out.LastEvaluatedKey;
      } while (ESK);
    },

    async ownerActiveCounts() {
      const counts = new Map();
      let ESK;
      do {
        const out = await ddb.send(new ScanCommand({
          TableName: T.properties,
          ProjectionExpression: 'ownerUserId, #s',
          ExpressionAttributeNames: { '#s': 'status' },
          ExclusiveStartKey: ESK,
        }));
        for (const it of (out.Items || [])) {
          const o = it.ownerUserId;
          if (!o || it.status === 'removed' || it.status === 'paused') continue;
          counts.set(o, (counts.get(o) || 0) + 1);
        }
        ESK = out.LastEvaluatedKey;
      } while (ESK);
      return counts;
    },
  };
}
