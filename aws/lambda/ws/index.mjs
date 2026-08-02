// WebSocket connection manager: $connect / $disconnect / subscribe.
//
// Stores connectionId ↔ matchId in the connections table so the broadcaster
// can push new messages to the right clients.

import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import {
  DynamoDBDocumentClient,
  PutCommand,
  DeleteCommand,
  UpdateCommand,
  GetCommand,
  QueryCommand,
} from '@aws-sdk/lib-dynamodb';

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const TABLE = process.env.CONNECTIONS_TABLE;
const TABLE_PREFIX = process.env.TABLE_PREFIX || 'rentch-';
const PROPERTIES_TABLE = `${TABLE_PREFIX}properties`;
const MESSAGES_TABLE = `${TABLE_PREFIX}messages`;

// Mirror of the router's chat-membership rule so a stranger can't subscribe to
// (and then receive live pushes for) someone else's thread. matchId is either
// "match-<propertyId>~<tenantUid>" (exact: embedded tenant + property owner) or
// legacy "match-<propertyId>" (owner or anyone who already posted). Fails OPEN on
// an unexpected lookup error so a transient DynamoDB blip never silently breaks a
// legitimate user's live chat; a genuine non-member still returns false.
async function isOwnerOf(propertyId, uid) {
  const prop = await ddb.send(new GetCommand({
    TableName: PROPERTIES_TABLE, Key: { id: propertyId },
  }));
  return !!(prop.Item && prop.Item.ownerUserId === uid);
}

async function isThreadMember(matchId, uid) {
  if (!uid || !matchId) return false;
  const rest = matchId.startsWith('match-') ? matchId.slice(6) : matchId;
  const sep = rest.lastIndexOf('~');
  try {
    if (sep >= 0) {
      const propertyId = rest.slice(0, sep);
      const tenantUid = rest.slice(sep + 1);
      if (uid === tenantUid) return true;
      return await isOwnerOf(propertyId, uid);
    }
    if (await isOwnerOf(rest, uid)) return true;
    const msgs = await ddb.send(new QueryCommand({
      TableName: MESSAGES_TABLE,
      IndexName: 'matchId-createdAt',
      KeyConditionExpression: 'matchId = :m',
      ExpressionAttributeValues: { ':m': matchId },
      Limit: 200,
    }));
    return (msgs.Items || []).some((m) => m.senderId === uid);
  } catch (e) {
    // Fail CLOSED (matches the REST router). A transient DB error must not let a
    // non-member attach to a thread and receive its live message stream.
    console.error('ws isThreadMember error (failing closed):', e);
    return false;
  }
}

export const handler = async (event) => {
  const { routeKey, connectionId } = event.requestContext;
  try {
    switch (routeKey) {
      case '$connect': {
        const uid = event.requestContext.authorizer?.uid || 'unknown';
        await ddb.send(new PutCommand({
          TableName: TABLE,
          Item: { connectionId, uid, matchId: 'none', connectedAt: Date.now() },
        }));
        return { statusCode: 200 };
      }
      case '$disconnect': {
        await ddb.send(new DeleteCommand({
          TableName: TABLE,
          Key: { connectionId },
        }));
        return { statusCode: 200 };
      }
      case 'subscribe': {
        const body = event.body ? JSON.parse(event.body) : {};
        const matchId = body.matchId;
        if (matchId) {
          // The WebSocket authorizer only runs on $connect, so the verified uid
          // was stored on the connection row then — read it back here.
          const conn = await ddb.send(new GetCommand({
            TableName: TABLE, Key: { connectionId },
          }));
          const uid = conn.Item?.uid;
          if (!(await isThreadMember(matchId, uid))) {
            console.warn('ws subscribe denied for', uid, 'on', matchId);
            return { statusCode: 403 };
          }
          await ddb.send(new UpdateCommand({
            TableName: TABLE,
            Key: { connectionId },
            UpdateExpression: 'SET matchId = :m',
            ExpressionAttributeValues: { ':m': matchId },
          }));
        }
        return { statusCode: 200 };
      }
      default:
        return { statusCode: 200 };
    }
  } catch (e) {
    console.error('WS handler error:', e);
    return { statusCode: 500 };
  }
};
