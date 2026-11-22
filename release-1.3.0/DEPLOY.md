# Axiom 1.3.0 Deployment Guide

This document contains the exact sequential steps to configure and deploy Axiom 1.3.0 to production.

---

### Step 1: Configure Cloud Secrets in Google Secret Manager

Firebase Cloud Functions v2 requires three secrets defined in Secret Manager:

```bash
# 1. Google Gemini API Key for vision, OCR, RAG, and extraction
firebase functions:secrets:set GEMINI_API_KEY
# Enter your Gemini API key (e.g. AIzaSy...)

# 2. RevenueCat Secret API Key (for server syncEntitlements REST calls)
firebase functions:secrets:set REVENUECAT_SECRET_KEY
# Enter your RevenueCat v1 REST API secret key (e.g. sk_...)

# 3. RevenueCat Webhook Secret Header (for verifying incoming webhooks)
firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET
# Enter a secure random string (e.g. openssl rand -hex 24)
```

Verify secrets are properly bound:
```bash
firebase functions:secrets:access GEMINI_API_KEY
```

---

### Step 2: Deploy Cloud Functions

Deploy the v2 Cloud Functions codebase:
```bash
firebase deploy --only functions
```

Functions deployed:
- `revenuecatWebhook` (v2 HTTPS onRequest)
- `syncEntitlements` (v2 Callable, App Check enforced)
- `analyzeAsset` (v2 Callable, App Check enforced)
- `extractEvents` (v2 Callable, App Check enforced)
- `chatWithRag` (v2 Callable, App Check enforced)
- `synthesizeCreation` (v2 Callable, App Check enforced)
- `generateStoryboard` (v2 Callable, App Check enforced)
- `generateTitle` (v2 Callable, App Check enforced)
- `enhanceText` (v2 Callable, App Check enforced)
- `getEmbedding` (v2 Callable, App Check enforced)
- `updateChatTitle` (v2 Callable, App Check enforced)
- `analyzeMedia` (v2 Callable, App Check enforced)
- `deleteAccount` (v2 Callable, App Check enforced)

Note the deployed URL for `revenuecatWebhook`:
`https://<region>-<project-id>.cloudfunctions.net/revenuecatWebhook`

---

### Step 3: Deploy Firestore Security Rules

Deploy the hardened, isolated security rules:
```bash
firebase deploy --only firestore:rules
```

Verify in Firebase Console -> Firestore -> Rules that:
- Global `match /{document=**}` read/write rule is absent.
- Rule on `/users/{userId}` denies client writes to `accountTier`, `tier`, `aiUsageCount`, `dailyUploadCount`, and `lastUploadDate`.

---

### Step 4: Deploy Storage Security Rules

Deploy the storage isolation and file constraint rules:
```bash
firebase deploy --only storage
```

Verify in Firebase Console -> Storage -> Rules that uploads are restricted to `users/{userId}/**`, capped at 25MB, and limited to images, audio, PDF, text, and Word documents.

---

### Step 5: Configure RevenueCat Webhook

1. Log into your [RevenueCat Dashboard](https://app.revenuecat.com).
2. Navigate to **Project Settings** -> **Integrations** -> **Webhooks**.
3. Click **Add Webhook**.
4. Configure the webhook settings:
   - **Webhook URL**: `https://<region>-<project-id>.cloudfunctions.net/revenuecatWebhook`
   - **Authorization Header**: Enter the exact secret string you set in `REVENUECAT_WEBHOOK_SECRET` in Step 1.
5. Save the integration and send a test event to verify the endpoint returns HTTP 200 `{ "success": true }`.

---

### Step 6: Build & Upload iOS App Archive (IPA)

On your macOS build machine with active Apple Developer signing certificates:

```bash
# Clean previous build artifacts
flutter clean
flutter pub get

# Build production archive
flutter build ipa --release

# Distribute to App Store Connect / TestFlight via Transporter or altool
xcrun altool --upload-app --type ios -f build/ios/ipa/*.ipa --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

---

### Rollback Strategy

If any critical issue arises during deployment:
1. **Cloud Functions**: Roll back functions to previous revision:
   ```bash
   gcloud functions deploy analyzeMedia --source ...
   ```
2. **Security Rules**: Revert rules instantly via Firebase Console History or CLI:
   ```bash
   firebase firestore:rules:release <PREVIOUS_RELEASE_ID>
   ```
3. **App Store**: In App Store Connect, halt phased release or reject the current build before marketing campaigns begin.
