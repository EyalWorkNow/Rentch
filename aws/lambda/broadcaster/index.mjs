// Broadcaster: triggered by the messages-table DynamoDB stream.
// On each new message, pushes it over WebSocket to every connection
// subscribed to that matchId. Cleans up stale (410) connections.

import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import {
  DynamoDBDocumentClient,
  QueryCommand,
  DeleteCommand,
} from '@aws-sdk/lib-dynamodb';
import {
  ApiGatewayManagementApiClient,
  PostToConnectionCommand,
} from '@aws-sdk/client-apigatewaymanagementapi';

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const TABLE = process.env.CONNECTIONS_TABLE;
const WS_ENDPOINT = process.env.WS_ENDPOINT; // https://{id}.execute-api.{region}.amazonaws.com/prod

const api = new ApiGatewayManagementApiClient({ endpoint: WS_ENDPOINT });

export const handler = async (event) => {
  for (const rec of event.Records || []) {
    if (rec.eventName !== 'INSERT') continue;
    const img = rec.dynamodb?.NewImage;
    if (!img) continue;

    const matchId = img.matchId?.S;
    if (!matchId) continue;

    const message = {
      id: img.id?.S,
      matchId,
      senderId: img.senderId?.S || '',
      senderName: img.senderName?.S || '',
      text: img.text?.S || '',
      createdAt: img.createdAt?.S || '',
    };

    const conns = await ddb.send(new QueryCommand({
      TableName: TABLE,
      IndexName: 'matchId-index',
      KeyConditionExpression: 'matchId = :m',
      ExpressionAttributeValues: { ':m': matchId },
    }));

    await Promise.all((conns.Items || []).map(async (c) => {
      try {
        await api.send(new PostToConnectionCommand({
          ConnectionId: c.connectionId,
          Data: Buffer.from(JSON.stringify(message)),
        }));
      } catch (e) {
        if (e.$metadata?.httpStatusCode === 410) {
          await ddb.send(new DeleteCommand({
            TableName: TABLE,
            Key: { connectionId: c.connectionId },
          }));
        } else {
          console.error('post error:', e.message);
        }
      }
    }));
  }
  return { statusCode: 200 };
};
