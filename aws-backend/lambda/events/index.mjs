import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand } from "@aws-sdk/lib-dynamodb";

const client = new DynamoDBClient({ region: process.env.AWS_REGION || "us-east-1" });
const db = DynamoDBDocumentClient.from(client);
const TABLE = process.env.EVENTS_TABLE || "rentch-events";

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type,Authorization",
};

export const handler = async (event) => {
  const method = event.httpMethod || event.requestContext?.http?.method;

  if (method === "OPTIONS") {
    return { statusCode: 200, headers, body: "" };
  }

  if (method !== "POST") {
    return { statusCode: 405, headers, body: JSON.stringify({ error: "Method not allowed" }) };
  }

  try {
    const body = JSON.parse(event.body || "{}");
    const { userId, eventType, sessionId, propertyId, matchId, metadata } = body;

    if (!userId || !eventType) {
      return { statusCode: 400, headers, body: JSON.stringify({ error: "userId and eventType required" }) };
    }

    const now = new Date();
    const id = `ev_${now.getTime()}_${Math.random().toString(36).slice(2, 6)}`;

    const item = {
      id,
      userId,
      eventType,
      sessionId: sessionId || "unknown",
      createdAt: now.toISOString(),
      ...(propertyId && { propertyId }),
      ...(matchId && { matchId }),
      ...(metadata && { metadata: typeof metadata === "string" ? metadata : JSON.stringify(metadata) }),
    };

    // Fire-and-forget style — don't block on failures
    await db.send(new PutCommand({ TableName: TABLE, Item: item }));

    return { statusCode: 201, headers, body: JSON.stringify({ success: true }) };
  } catch (err) {
    console.error("Events handler error:", err);
    // Return success anyway — event loss is acceptable
    return { statusCode: 200, headers, body: JSON.stringify({ success: true }) };
  }
};
