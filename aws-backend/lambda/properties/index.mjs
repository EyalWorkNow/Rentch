import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  DeleteCommand,
  QueryCommand,
  ScanCommand,
} from "@aws-sdk/lib-dynamodb";

const client = new DynamoDBClient({ region: process.env.AWS_REGION || "us-east-1" });
const db = DynamoDBDocumentClient.from(client);
const TABLE = process.env.PROPERTIES_TABLE || "rentch-properties";

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type,Authorization",
};

export const handler = async (event) => {
  const method = event.httpMethod || event.requestContext?.http?.method;
  const path = event.path || event.rawPath || "";

  if (method === "OPTIONS") {
    return { statusCode: 200, headers, body: "" };
  }

  try {
    // GET /properties — list active properties with pagination
    if (method === "GET" && !path.includes("/properties/")) {
      const qs = event.queryStringParameters || {};
      const limit = parseInt(qs.limit || "150");
      const status = qs.status || "active";
      const lastKey = qs.lastKey ? JSON.parse(decodeURIComponent(qs.lastKey)) : undefined;

      const result = await db.send(new QueryCommand({
        TableName: TABLE,
        IndexName: "status-index",
        KeyConditionExpression: "#s = :s",
        ExpressionAttributeNames: { "#s": "status" },
        ExpressionAttributeValues: { ":s": status },
        Limit: limit,
        ExclusiveStartKey: lastKey,
      }));

      return {
        statusCode: 200,
        headers,
        body: JSON.stringify({
          rows: result.Items || [],
          hasMore: !!result.LastEvaluatedKey,
          lastKey: result.LastEvaluatedKey
            ? encodeURIComponent(JSON.stringify(result.LastEvaluatedKey))
            : null,
        }),
      };
    }

    // GET /properties/{id}
    if (method === "GET" && path.includes("/properties/")) {
      const propertyId = path.split("/").pop();
      const result = await db.send(new GetCommand({
        TableName: TABLE,
        Key: { propertyId },
      }));

      if (!result.Item) {
        return { statusCode: 404, headers, body: JSON.stringify({ error: "Not found" }) };
      }
      return { statusCode: 200, headers, body: JSON.stringify(result.Item) };
    }

    // POST /properties — create or update
    if (method === "POST" || method === "PUT") {
      const body = JSON.parse(event.body || "{}");
      if (!body.propertyId) {
        return { statusCode: 400, headers, body: JSON.stringify({ error: "propertyId required" }) };
      }

      body.updatedAt = new Date().toISOString();
      if (!body.createdAt) body.createdAt = body.updatedAt;

      await db.send(new PutCommand({ TableName: TABLE, Item: body }));

      return { statusCode: 200, headers, body: JSON.stringify({ success: true, id: body.propertyId }) };
    }

    // DELETE /properties/{id}
    if (method === "DELETE") {
      const propertyId = path.split("/").pop();
      await db.send(new DeleteCommand({
        TableName: TABLE,
        Key: { propertyId },
      }));
      return { statusCode: 200, headers, body: JSON.stringify({ success: true }) };
    }

    return { statusCode: 405, headers, body: JSON.stringify({ error: "Method not allowed" }) };
  } catch (err) {
    console.error("Properties handler error:", err);
    return { statusCode: 500, headers, body: JSON.stringify({ error: err.message }) };
  }
};
