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
} from '@aws-sdk/lib-dynamodb';

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const TABLE = process.env.CONNECTIONS_TABLE;

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
