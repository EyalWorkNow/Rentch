#!/usr/bin/env node

/**
 * Cleanup Script: Delete App Store Review Test User
 *
 * Removes the review@test.com account and associated data from:
 * - Firebase Auth
 * - DynamoDB users table
 * - DynamoDB properties table (sample entries)
 *
 * Usage:
 *   export FIREBASE_PROJECT_ID=your-project
 *   export FIREBASE_CREDENTIALS_PATH=./serviceAccountKey.json
 *   export AWS_REGION=us-east-1
 *   node scripts/delete-app-store-review-user.mjs
 */

import admin from 'firebase-admin';
import { DynamoDBDocumentClient, GetCommand, DeleteCommand, ScanCommand } from '@aws-sdk/lib-dynamodb';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import readline from 'readline';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Config
const REVIEW_EMAIL = 'review@test.com';
const TABLE_PREFIX = process.env.AWS_DYNAMODB_TABLE_PREFIX || 'rently-';
const REGION = process.env.AWS_REGION || 'us-east-1';

const firebaseCredentialsPath = process.env.FIREBASE_CREDENTIALS_PATH ||
  path.join(__dirname, '../firebase-service-account.json');

if (!fs.existsSync(firebaseCredentialsPath)) {
  console.error(`❌ Firebase credentials not found: ${firebaseCredentialsPath}`);
  process.exit(1);
}

const firebaseCredentials = JSON.parse(
  fs.readFileSync(firebaseCredentialsPath, 'utf8')
);

admin.initializeApp({
  credential: admin.credential.cert(firebaseCredentials),
  projectId: firebaseCredentials.project_id,
});

const auth = admin.auth();

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }), {
  marshallOptions: { removeUndefinedValues: true },
});

// Helpers
function prompt(question) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
    });
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.toLowerCase());
    });
  });
}

async function deleteFirebaseUser() {
  try {
    const user = await auth.getUserByEmail(REVIEW_EMAIL).catch(() => null);
    if (!user) {
      console.log(`⊘ Firebase user not found (already deleted?)`);
      return null;
    }

    await auth.deleteUser(user.uid);
    console.log(`✓ Firebase user deleted (was UID: ${user.uid})`);
    return user.uid;
  } catch (error) {
    console.error('❌ Firebase error:', error.message);
    throw error;
  }
}

async function deleteDynamoDBUserRecord(uid) {
  try {
    const usersTable = `${TABLE_PREFIX}users`;

    if (!uid) {
      console.log(`⊘ No UID to delete from DynamoDB users table`);
      return;
    }

    await ddb.send(
      new DeleteCommand({
        TableName: usersTable,
        Key: { id: uid },
      })
    );

    console.log(`✓ DynamoDB user record deleted`);
  } catch (error) {
    console.error('❌ DynamoDB error:', error.message);
    throw error;
  }
}

async function deleteSampleProperties() {
  try {
    const propertiesTable = `${TABLE_PREFIX}properties`;

    // Scan for sample properties (tagged with "review-sample-" prefix)
    const scanResult = await ddb.send(
      new ScanCommand({
        TableName: propertiesTable,
        FilterExpression: 'begins_with(id, :prefix)',
        ExpressionAttributeValues: {
          ':prefix': 'review-sample-',
        },
      })
    );

    const items = scanResult.Items || [];
    console.log(`Found ${items.length} sample property(ies) to delete`);

    for (const item of items) {
      await ddb.send(
        new DeleteCommand({
          TableName: propertiesTable,
          Key: { id: item.id },
        })
      );
      console.log(`  ✓ Deleted property: ${item.id}`);
    }

    return items.length;
  } catch (error) {
    console.error('❌ Sample properties cleanup error:', error.message);
    throw error;
  }
}

async function main() {
  try {
    console.log(`\n🗑️  Deleting App Store Review Test Account\n`);
    console.log(`📧 Account: ${REVIEW_EMAIL}\n`);

    // Confirmation
    const confirm = await prompt('Are you sure you want to delete this account and all associated data? (yes/no): ');
    if (confirm !== 'yes') {
      console.log('\n⊘ Deletion cancelled.\n');
      process.exit(0);
    }

    console.log('');

    // Delete Firebase user
    console.log('Step 1: Deleting Firebase Auth user...');
    const uid = await deleteFirebaseUser();

    // Delete DynamoDB user record
    console.log('Step 2: Deleting DynamoDB user record...');
    await deleteDynamoDBUserRecord(uid);

    // Delete sample properties
    console.log('Step 3: Deleting sample properties...');
    const deletedCount = await deleteSampleProperties();

    console.log(`\n✅ Cleanup complete!\n`);
    console.log(`Summary:`);
    console.log(`  - Firebase user: deleted`);
    console.log(`  - DynamoDB user record: deleted`);
    console.log(`  - Sample properties: ${deletedCount} deleted\n`);

    process.exit(0);
  } catch (error) {
    console.error('\n❌ Fatal error:', error);
    process.exit(1);
  }
}

main();
