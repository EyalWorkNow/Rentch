import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  PutCommand,
  QueryCommand,
} from "@aws-sdk/lib-dynamodb";

const client = new DynamoDBClient({ region: process.env.AWS_REGION || "us-east-1" });
const db = DynamoDBDocumentClient.from(client);
const TABLE = process.env.MESSAGES_TABLE || "rentch-messages";

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type,Authorization",
};

export const handler = async (event) => {
  const method = event.httpMethod || event.requestContext?.http?.method;

  if (method === "OPTIONS") {
    return { statusCode: 200, headers, body: "" };
  }

  try {
    // GET /messages?matchId=xxx&limit=100&afterId=xxx
    if (method === "GET") {
      const qs = event.queryStringParameters || {};
      const matchId = qs.matchId;
      if (!matchId) {
        return { statusCode: 400, headers, body: JSON.stringify({ error: "matchId required" }) };
      }

      const limit = parseInt(qs.limit || "100");
      const lastKey = qs.lastKey ? JSON.parse(decodeURIComponent(qs.lastKey)) : undefined;

      const result = await db.send(new QueryCommand({
        TableName: TABLE,
        IndexName: "matchId-createdAt-index",
        KeyConditionExpression: "matchId = :m",
        ExpressionAttributeValues: { ":m": matchId },
        ScanIndexForward: true,
        Limit: limit,
        ExclusiveStartKey: lastKey,
      }));

      return {
        statusCode: 200,
        headers,
        body: JSON.stringify({
          rows: result.Items || [],
          lastKey: result.LastEvaluatedKey
            ? encodeURIComponent(JSON.stringify(result.LastEvaluatedKey))
            : null,
        }),
      };
    }

    // POST /messages — send a message
    if (method === "POST") {
      const body = JSON.parse(event.body || "{}");
      const { matchId, senderId, senderName, text } = body;

      if (!matchId || !senderId || !text) {
        return {
          statusCode: 400,
          headers,
          body: JSON.stringify({ error: "matchId, senderId, text required" }),
        };
      }

      const now = new Date();
      const id = `msg_${now.getTime()}_${Math.random().toString(36).slice(2, 7)}`;

      const item = {
        id,
        matchId,
        senderId,
        senderName: senderName || senderId,
        text,
        createdAt: now.toISOString(),
      };

      await db.send(new PutCommand({ TableName: TABLE, Item: item }));

      return { statusCode: 201, headers, body: JSON.stringify(item) };
    }

    return { statusCode: 405, headers, body: JSON.stringify({ error: "Method not allowed" }) };
  } catch (err) {
    console.error("Messages handler error:", err);
    return { statusCode: 500, headers, body: JSON.stringify({ error: err.message }) };
  }
};
