# Chat — Appwrite Setup Guide

One-time setup to enable real-time, cross-device chat between matched users.

---

## 1. Create the `messages` Collection

In the Appwrite Console → Databases → your database:

**Create Collection:** `messages`

| Attribute | Type | Size | Required |
|-----------|------|------|----------|
| `matchId` | String | 64 | Yes |
| `senderId` | String | 64 | Yes |
| `senderName` | String | 100 | Yes |
| `text` | String | 2000 | Yes |
| `createdAt` | String | 32 | Yes |

**Indexes:**

| Key | Type | Attributes | Order |
|-----|------|-----------|-------|
| `matchId_idx` | Key | matchId | ASC |
| `createdAt_idx` | Key | createdAt | ASC |

**Permissions:**

| Role | Permission |
|------|-----------|
| Users | Create |
| Users | Read |

---

## 2. Enable Realtime

In Appwrite Console → Realtime → ensure it is enabled for your project.

No extra configuration needed — Realtime is on by default in Appwrite Cloud.

---

## 3. Set the Collection ID in Build Flags

Find your collection's `$id` in the Appwrite console (e.g. `6b1234abc000def567`).

### Development run:
```bash
flutter run \
  --dart-define=APPWRITE_MESSAGES_TABLE_ID=6b1234abc000def567
```

### iOS release:
```bash
flutter build ipa \
  --dart-define=APPWRITE_MESSAGES_TABLE_ID=6b1234abc000def567 \
  --obfuscate \
  --split-debug-info=build/debug-info
```

### Android release:
```bash
flutter build apk \
  --dart-define=APPWRITE_MESSAGES_TABLE_ID=6b1234abc000def567 \
  --obfuscate \
  --split-debug-info=build/debug-info
```

If `APPWRITE_MESSAGES_TABLE_ID` is not set, the app falls back to local-only
chat (messages stored in each user's device — no cross-device sync).

---

## 4. How It Works (Architecture)

```
Tenant opens chat                 Landlord opens chat
(matchId: "match-property-123")  (matchId: "match-property-123")
         │                                │
         ▼                                ▼
  ChatProvider.initialize()       ChatProvider.initialize()
  ┌──────────────────────┐        ┌──────────────────────┐
  │ 1. Seed local msgs   │        │ 1. Seed local msgs   │
  │ 2. Fetch from AW     │        │ 2. Fetch from AW     │
  │ 3. Subscribe WS      │        │ 3. Subscribe WS      │
  │ 4. Poll every 15s    │        │ 4. Poll every 15s    │
  └──────────────────────┘        └──────────────────────┘
         │                                │
  Tenant types "שלום"                     │
  ChatProvider.sendMessage()              │
  ┌──────────────────────┐                │
  │ Optimistic add (UI)  │                │
  │ Write to Appwrite    │─────────────►  │
  │ Replace temp w/ real │   Realtime WS  ▼
  └──────────────────────┘   event     _onRemoteMessage()
                                       Landlord sees msg ✅
```

**Match ID is deterministic:** `'match-${propertyId}'`
Both users compute the same ID from the property — no server-side match
creation is needed for the chat to work.

---

## 5. Status Indicators in the App

The dot on the property avatar in the chat AppBar shows:

| Color | Meaning |
|-------|---------|
| 🟢 Green | Realtime WebSocket active — messages deliver instantly |
| 🟠 Orange | Connecting / reconnecting (messages still send via REST) |
| ⚫ Grey | Local mode — no Appwrite collection configured |

The label next to the message count changes accordingly:
- `"בשידור חי"` — live
- `"מתחבר..."` — connecting
- `"צ׳אט מקומי"` — local only

---

## 6. Message Delivery Guarantees

| Scenario | Behavior |
|----------|----------|
| WebSocket active | Message appears on both sides in < 500ms |
| WebSocket dropped | Message saved to Appwrite; other side gets it via 15s poll |
| No internet (sender) | Message shown as pending (grey, single tick); sent when reconnected |
| No internet (receiver) | Gets messages when they reconnect and screen loads |
| App backgrounded | 15s poll resumes when foreground (no background push needed) |

---

## 7. Security Notes

- Messages are sanitized before write (`InputSanitizer.sanitizeMessage`)
- Length enforced at client: 2,000 chars max
- Rate limited at client: 30 messages/minute
- Server-side: add an Appwrite Function trigger on `messages.create` to
  re-validate text length and strip HTML (see `docs/SCALE_INFRASTRUCTURE.md`)
- Permissions: currently `Users` (any logged-in user can read all messages).
  For production, restrict read to match participants using Appwrite Functions
  to set per-document permissions on create.
