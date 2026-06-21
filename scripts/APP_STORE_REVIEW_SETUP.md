# App Store Review Test Account Setup

## Overview
This script creates a dedicated test account for Apple's App Store Review team. The account is pre-verified and pre-populated with sample data so reviewers can see a "live" app experience without friction.

## Account Details
- **Email**: `review@test.com`
- **Password**: `Test1234`
- **Role**: Tenant (apartment seeker)
- **Status**: Fully verified (email verified, 2FA/OTP disabled)

## What Gets Set Up

### 1. Firebase Auth User
- ✅ Email/password authentication enabled
- ✅ Email marked as verified (no email confirmation flow)
- ✅ Display name: "App Store Review"

### 2. DynamoDB User Record
- User profile with verified flags set to `true`
- 2FA/OTP disabled (`twoFactorEnabled: false`, `otpEnabled: false`)
- Tagged as review account (`isReviewAccount: true`)
- Tenant preferences pre-filled (budget, city, rooms)

### 3. Sample Properties (Optional)
- 2 sample apartment listings in Tel Aviv (Florentine & Neve Tzedek)
- Verified listings so they appear prominently in search
- Different price points and features to showcase app breadth

## Prerequisites

1. **Firebase Admin SDK Credentials**
   ```bash
   # Download from Firebase Console → Project Settings → Service Accounts
   # Save as: firebase-service-account.json (in repo root)
   ```

2. **AWS Credentials**
   ```bash
   export AWS_REGION=us-east-1
   export AWS_ACCESS_KEY_ID=your-key
   export AWS_SECRET_ACCESS_KEY=your-secret
   ```

3. **Node.js 18+** with npm/yarn

## Installation

```bash
# Install dependencies (one-time)
npm install firebase-admin @aws-sdk/client-dynamodb @aws-sdk/lib-dynamodb

# Or with yarn:
yarn add firebase-admin @aws-sdk/client-dynamodb @aws-sdk/lib-dynamodb
```

## Execution

```bash
# Set environment variables
export FIREBASE_PROJECT_ID=your-rently-project
export FIREBASE_CREDENTIALS_PATH=./firebase-service-account.json
export AWS_REGION=us-east-1
export AWS_DYNAMODB_TABLE_PREFIX=rently-

# Run the seed script
node scripts/create-app-store-review-user.mjs
```

## What Happens

```
🔐 Creating App Store Review Test Account

📧 Email: review@test.com
🔑 Password: Test1234

Step 1: Creating Firebase Auth user...
✓ Firebase user created (UID: abc123xyz...)

Step 2: Creating DynamoDB user record...
✓ DynamoDB user record created in table: rently-users

Step 3: Seeding sample properties...
✓ Seeded 2 sample properties

✅ App Store Review account ready!
```

## Testing Checklist for Reviewers

When Apple's review team logs in, they should verify:

- [ ] Login with `review@test.com` / `Test1234` succeeds
- [ ] No email verification email is sent or required
- [ ] No OTP/2FA flow is triggered
- [ ] Tenant dashboard loads with search suggestions
- [ ] Sample properties appear in apartment search results
- [ ] Can browse property details without friction
- [ ] Can navigate all major app flows (search, messaging, profile)
- [ ] App handles edge cases gracefully (network errors, empty states)

## Cleanup (Optional)

To remove the test account after review:

```bash
# Firebase Console → Authentication → Find review@test.com → Delete
# AWS Console → DynamoDB → rently-users table → Scan for id="review..." → Delete
```

Or programmatically:

```bash
node scripts/delete-app-store-review-user.mjs
```

## Notes

- **No email verification flow**: The `emailVerified: true` flag in Firebase bypasses any email confirmation checks.
- **2FA/OTP disabled**: `twoFactorEnabled` and `otpEnabled` are set to `false`, so no SMS or authenticator app is required.
- **Sample data**: The 2 sample properties are tagged with a recognizable `ownerUserId` (starting with `landlord-sample-`) so they're easy to identify and delete later.
- **Idempotent**: Running the script twice won't duplicate the account—it checks if the user exists first.

## Troubleshooting

### "Firebase credentials not found"
```bash
# Make sure the file path matches:
export FIREBASE_CREDENTIALS_PATH=./firebase-service-account.json
ls -la firebase-service-account.json
```

### "DynamoDB error: ResourceNotFoundException"
```bash
# Verify table prefix and AWS region match your deployment:
export AWS_DYNAMODB_TABLE_PREFIX=rently-
export AWS_REGION=us-east-1
```

### "Firebase Auth error: email-already-in-use"
The account already exists. You can:
1. Run the script again (it will skip creation and return the UID)
2. Or delete the user from Firebase Console and re-run
