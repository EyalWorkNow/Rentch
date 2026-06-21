#!/usr/bin/env node

/**
 * Seed Script: Create App Store Review Test User
 *
 * Purpose:
 * - Creates Firebase Auth user: review@test.com / Test1234
 * - Marks email as verified (bypasses email verification flow)
 * - Creates DynamoDB user record with verified flag
 * - Populates with sample data so app doesn't appear empty on first login
 *
 * Usage:
 *   export FIREBASE_PROJECT_ID=your-project
 *   export FIREBASE_CREDENTIALS_PATH=./serviceAccountKey.json
 *   export AWS_REGION=us-east-1
 *   export AWS_DYNAMODB_TABLE_PREFIX=rently-
 *   node scripts/create-app-store-review-user.mjs
 */

import admin from 'firebase-admin';
import { DynamoDBDocumentClient, PutCommand } from '@aws-sdk/lib-dynamodb';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ═════════════════════════════════════════════════════════════════════════════
// Config

const REVIEW_EMAIL = 'review@test.com';
const REVIEW_PASSWORD = 'Test1234';
const TABLE_PREFIX = process.env.AWS_DYNAMODB_TABLE_PREFIX || 'rently-';
const REGION = process.env.AWS_REGION || 'us-east-1';

// Firebase Admin SDK
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

// DynamoDB
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }), {
  marshallOptions: { removeUndefinedValues: true },
});

// ═════════════════════════════════════════════════════════════════════════════
// Helpers

async function createFirebaseUser() {
  try {
    // Check if user already exists
    const existing = await auth.getUserByEmail(REVIEW_EMAIL).catch(() => null);
    if (existing) {
      console.log(`✓ Firebase user already exists (UID: ${existing.uid})`);
      return existing.uid;
    }

    // Create new user
    const userRecord = await auth.createUser({
      email: REVIEW_EMAIL,
      password: REVIEW_PASSWORD,
      displayName: 'App Store Review',
      emailVerified: true, // ✓ Bypass email verification
    });

    console.log(`✓ Firebase user created (UID: ${userRecord.uid})`);
    return userRecord.uid;
  } catch (error) {
    console.error('❌ Firebase Auth error:', error.message);
    throw error;
  }
}

async function createDynamoDBUserRecord(uid) {
  try {
    const usersTable = `${TABLE_PREFIX}users`;

    // Sample tenant profile (review user is a tenant looking for apartments)
    const userRecord = {
      id: uid,
      email: REVIEW_EMAIL,
      displayName: 'App Store Review',
      role: 'tenant', // Can be changed to 'landlord' if needed
      isVerified: true,
      emailVerified: true,
      phoneVerified: false,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),

      // Tenant profile
      tenantProfile: {
        name: 'App Store Review',
        age: 28,
        budget: 7000,
        desiredRooms: 2,
        city: 'תל אביב',
        moveInWindow: 'גמיש',
        bio: 'Looking for a comfortable apartment in Tel Aviv',
        photoUrl: '',
      },

      // Bypass 2FA/OTP
      twoFactorEnabled: false,
      otpEnabled: false,

      // App Store Review metadata
      isReviewAccount: true,
      reviewAccountNotes: 'Official App Store Review test account',
    };

    await ddb.send(
      new PutCommand({
        TableName: usersTable,
        Item: userRecord,
      })
    );

    console.log(`✓ DynamoDB user record created in table: ${usersTable}`);
  } catch (error) {
    console.error('❌ DynamoDB error:', error.message);
    throw error;
  }
}

async function seedSampleProperties(uid) {
  try {
    const propertiesTable = `${TABLE_PREFIX}properties`;

    // Sample properties (so app doesn't appear empty on first login)
    const sampleProperties = [
      {
        id: `review-sample-1-${Date.now()}`,
        ownerUserId: 'landlord-sample-001',
        city: 'תל אביב',
        neighborhood: 'פלורנטין',
        street: 'שדרות מוטה גור',
        streetNumber: 123,
        price: 6500,
        rooms: 2,
        sizeM2: 75,
        floor: '3',
        totalFloors: '5',
        propertyType: 'דירה',
        entryDate: '2026-07-01',
        condition: 'טוב',
        lat: 32.0613,
        lon: 34.7642,
        status: 'active',
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        url: '',
        agencyListing: false,
        ownerName: 'Test Landlord',
        features: ['feat_renovated', 'feat_pets', 'feat_parking'],
        media: [],
        description: 'Beautiful 2-room apartment in the heart of Florentine',
        verified: true,
        isVerifiedListing: true,
        hasCameraVideo: true,
      },
      {
        id: `review-sample-2-${Date.now()}`,
        ownerUserId: 'landlord-sample-002',
        city: 'תל אביב',
        neighborhood: 'נווה צדק',
        street: 'רח׳ יקי ירושלמי',
        streetNumber: 45,
        price: 7500,
        rooms: 3,
        sizeM2: 95,
        floor: '2',
        totalFloors: '4',
        propertyType: 'דירה',
        entryDate: '2026-08-15',
        condition: 'ממש טוב',
        lat: 32.0521,
        lon: 34.7600,
        status: 'active',
        createdAt: new Date(Date.now() - 86400000).toISOString(),
        updatedAt: new Date().toISOString(),
        url: '',
        agencyListing: false,
        ownerName: 'Another Landlord',
        features: ['feat_renovated', 'feat_modern_appliances'],
        media: [],
        description: 'Spacious 3-room apartment in Neve Tzedek with modern kitchen',
        verified: true,
        isVerifiedListing: true,
        hasCameraVideo: true,
      },
    ];

    for (const prop of sampleProperties) {
      await ddb.send(
        new PutCommand({
          TableName: propertiesTable,
          Item: prop,
        })
      );
    }

    console.log(`✓ Seeded ${sampleProperties.length} sample properties`);
  } catch (error) {
    console.error('❌ Sample properties seeding error:', error.message);
    throw error;
  }
}

async function main() {
  try {
    console.log(`\n🔐 Creating App Store Review Test Account\n`);
    console.log(`📧 Email: ${REVIEW_EMAIL}`);
    console.log(`🔑 Password: ${REVIEW_PASSWORD}\n`);

    // 1. Create Firebase Auth user (with verified email)
    console.log('Step 1: Creating Firebase Auth user...');
    const uid = await createFirebaseUser();

    // 2. Create DynamoDB user record
    console.log('Step 2: Creating DynamoDB user record...');
    await createDynamoDBUserRecord(uid);

    // 3. Seed sample properties (optional, but makes app feel "alive")
    console.log('Step 3: Seeding sample properties...');
    await seedSampleProperties(uid);

    console.log(`\n✅ App Store Review account ready!\n`);
    console.log(`Test these scenarios:\n`);
    console.log(`  1. Login with ${REVIEW_EMAIL} / ${REVIEW_PASSWORD}`);
    console.log(`  2. Verify email verification is skipped`);
    console.log(`  3. Verify 2FA/OTP is bypassed`);
    console.log(`  4. Confirm sample properties appear in tenant search`);
    console.log(`  5. Test basic flows (browse, message, profile)\n`);

    process.exit(0);
  } catch (error) {
    console.error('\n❌ Fatal error:', error);
    process.exit(1);
  }
}

main();
