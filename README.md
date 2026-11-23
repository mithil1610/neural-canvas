# Axiom – Your AI Second Brain 🧠

Axiom is an intelligent personal Second Brain and digital memory canvas built with Flutter, Firebase, and Google Gemini. It ingests your thoughts, screenshots, voice notes, and documents, automatically extracts actionable events, organizes them into a searchable relational knowledge graph, and surfaces memory reels and multi-modal insights.

---

## 🏗 Architecture Overview

```
                      ┌───────────────────────────────────────┐
                      │              Flutter App              │
                      │ (iOS, App Check, RevenueCat SDK)      │
                      └──────────────────┬────────────────────┘
                                         │
                 ┌───────────────────────┼───────────────────────┐
                 │                       │                       │
                 ▼                       ▼                       ▼
      ┌────────────────────┐   ┌───────────────────┐   ┌───────────────────┐
      │  Firebase Auth     │   │ Cloud Firestore   │   │ Firebase Storage  │
      │  (User identity)   │   │ (Isolated vaults) │   │ (Assets/Uploads)  │
      └────────────────────┘   └───────────────────┘   └───────────────────┘
                                         ▲
                                         │ Admin SDK
                                         ▼
                      ┌───────────────────────────────────────┐
                      │    Cloud Functions v2 (Node.js 22)    │
                      │  - Quotas (Tier limits in transaction)│
                      │  - Server RAG (Capped context)        │
                      │  - Event Extraction (Local timezone)  │
                      │  - RevenueCat Webhook & Entitlements  │
                      │  - Automated Purge / Account Deletion │
                      └──────────────────┬────────────────────┘
                                         │
                                         ▼
                      ┌───────────────────────────────────────┐
                      │  Google Gemini 2.5 Flash / Embeddings │
                      │  (Key stored in Secret Manager)       │
                      └───────────────────────────────────────┘
```

- **Client**: Flutter (Dart 3.x), Material 3 Dark theme, Local Biometrics (Secure Enclave), Local Notifications (timezone-aware). Zero direct AI keys compiled into client.
- **Backend**: Firebase Cloud Functions v2 (Node.js 22), enforced App Check, Secret Manager, Firestore Transactions for strict quota enforcement.
- **Subscriptions**: RevenueCat StoreKit integration (`purchases_flutter`) verified via server-side RevenueCat webhooks and `syncEntitlements` callable.
- **Security Rules**: Isolated per-user Firestore and Storage rules preventing unauthorized cross-user access and blocking client writes to protected tier and quota counters.

---

## 🔒 Required Secrets (Google Cloud / Firebase Secret Manager)

Cloud Functions access secrets via Cloud Secret Manager (`defineSecret`):

| Secret Name | Purpose | Example Value |
|---|---|---|
| `GEMINI_API_KEY` | Google Gemini API key for analysis, RAG, and extraction | `AIzaSy...` |
| `REVENUECAT_SECRET_KEY` | RevenueCat REST API v1 Secret Key (for `syncEntitlements`) | `sk_...` |
| `REVENUECAT_WEBHOOK_SECRET` | Secret bearer token for authenticating RevenueCat webhooks | User-defined random hex |

To set up secrets:
```bash
firebase functions:secrets:set GEMINI_API_KEY
firebase functions:secrets:set REVENUECAT_SECRET_KEY
firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET
```

---

## 💻 Running with Firebase Emulators

The repository includes pre-configured emulator settings in `firebase.json` for Firestore, Storage, Functions, and Auth.

### 1. Prerequisites
- Node.js 22+
- Java 17+ (or JRE on system PATH)
- Firebase CLI (`npm install -g firebase-tools`)

### 2. Start the Emulators
```bash
firebase emulators:start
```
The Emulator UI will be accessible at `http://localhost:4000`.

### 3. Run Security Rules Unit Tests
```bash
cd test/rules
npm install
npm test
```
Or run against an active emulator instance:
```bash
firebase emulators:exec --only firestore,storage "npm --prefix test/rules test"
```

---

### App Check debug token (simulator / Xcode builds)
Debug builds use `AppleDebugProvider`. Run the app once from Xcode, copy the
`Firebase App Check debug token` line from the console, and add it in
Firebase Console → App Check → Apps → Manage debug tokens. Without it, every
Cloud Function call fails with `unauthenticated`/`permission-denied` in debug.

### Cloud Functions tests
```bash
cd functions && npm ci && npm test   # helper + end-to-end handler tests, no emulator needed
```

## 🚀 Deploying to Production

> Follow `release-1.3.0/DEPLOY.md`: strict Firestore rules ship in Phase B, after 1.3.0 adoption.

### 1. Deploy Cloud Functions
```bash
firebase deploy --only functions
```

### 2. Deploy Firestore & Storage Rules
```bash
firebase deploy --only firestore:rules
firebase deploy --only storage
```

### 3. Configure RevenueCat Webhook URL
In your RevenueCat Dashboard -> Project -> Integrations -> Webhooks:
- **Webhook URL**: `https://<region>-<project-id>.cloudfunctions.net/revenuecatWebhook`
- **Authorization Header**: Set to the value stored in `REVENUECAT_WEBHOOK_SECRET`.

---

## 📱 Building the App

### Running Locally
```bash
flutter pub get
flutter run
```

### Building iOS Release Archive (IPA)
```bash
flutter build ipa --release
```
*Note: iOS release archives must be built on macOS with Xcode and active Apple Developer signing certificates.*
