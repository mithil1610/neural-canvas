# Axiom 1.3.0 Technical Changelog

Release Date: November 2026  
Target Version: 1.3.0 (Build 2)  
Platforms: iOS (App Store)

---

### 1. Security & Firestore Rules Hardening
- **Removed Global Wildcard Access**: Completely removed the permissive `match /{document=**} allow read, write: if request.auth != null;` rule which had previously allowed any authenticated user to read and mutate all users' documents.
- **Strict User Isolation**: Implemented isolated match block on `/users/{userId}` ensuring users can only read and write their own documents and subcollections (`/users/{userId}/**`).
- **Client Mutation Protection on Sensitive Fields**: Prohibited client writes on `/users/{userId}` for:
  - `accountTier`
  - `tier`
  - `aiUsageCount`
  - `dailyUploadCount`
  - `lastUploadDate`
  Enforced both on `create` (via `!request.resource.data.keys().hasAny(...)`) and on `update` (via `!request.resource.data.diff(resource.data).affectedKeys().hasAny(...)`).
- **Comprehensive Storage Rules**: Added `storage.rules` registered in `firebase.json`:
  - Path restricted strictly to `users/{userId}/**`.
  - Max upload size enforced at 25MB (`request.resource.size <= 25 * 1024 * 1024`).
  - Allowed content types restricted to: `image/*`, `audio/*`, `application/pdf`, `text/plain`, `application/msword`, and `application/vnd.openxmlformats-officedocument.wordprocessingml.document`.
- **Automated Rules Unit Tests**: Added full test suite in `test/rules/` with 21 unit tests covering Firestore and Storage rules against the Firebase local emulator.

---

### 2. Server-Side Subscription Tier & Entitlement Sync
- **RevenueCat Webhook (v2 HTTPS)**: Added `revenuecatWebhook` in Cloud Functions verified with a secret authorization header stored in Secret Manager (`REVENUECAT_WEBHOOK_SECRET`). Maps incoming entitlement events (`infinite_brain` and `creation_engine`) to `users/{app_user_id}.accountTier` ("Infinite Brain", "Creation Engine", or "Free").
- **App User ID Alignment**: Configured `Purchases.logIn(uid)` on Firebase sign-in and `Purchases.logOut()` on sign-out to ensure identity continuity across StoreKit and Firebase.
- **Removed Client-Side Tier Writes**: Stripped client Firestore writes of `accountTier` from `main.dart`'s `CustomerInfoUpdateListener`, registration in `auth_gate.dart`, and paywall screen. The listener is now purely reactive for local UI refresh.
- **Callable `syncEntitlements`**: Implemented v2 callable function querying RevenueCat's v1 REST API for the caller's verified UID and updating `accountTier` atomically. Invoked immediately following in-app purchases and restoration.

---

### 3. Server-Side Gemini Execution & Quota Management
- **Complete Elimination of Client-Side AI Keys**: Removed `GEMINI_API_KEY` and the `google_generative_ai` package from the Flutter app. Grep analysis confirms zero references or keys compiled into the client binary.
- **Centralized Cloud Functions**:
  - `analyzeAsset`: Multimodal vision, audio, and PDF document OCR analysis and auto-categorization.
  - `extractEvents`: Timeline extraction with timezone awareness.
  - `chatWithRag`: RAG conversational querying with server-side knowledge vault retrieval capped to the top 15 items and 6,000 characters.
  - `synthesizeCreation`: Creative compilation and narrative synthesis.
  - `generateStoryboard`: Video arc narrative storyboard generator for cluster items.
  - `generateTitle`: Short 3-to-4 word auto-titler for notes and snippets.
  - `enhanceText`: Summary structure optimization for text notes.
  - `getEmbedding`: Vector embeddings via `text-embedding-004`.
  - `updateChatTitle`: Automated session titling based on opening conversation turns.
- **App Check Enforcement**: Every callable enforces App Check (`enforceAppCheck: true`) and strict user authentication.
- **Transaction-Based Quota Limits**: Enforced per-tier quotas inside Firestore transactions:
  - Free: 10 uploads/day, 30 chats/day, 200 monthly AI compute pool.
  - Creation Engine: 100 uploads/day, 250 chats/day, 750 monthly AI compute pool.
  - Infinite Brain: 1,000 uploads/day, 1,000 chats/day, 3,000 monthly AI compute pool.
  Returns clear `resource-exhausted` errors when limits are exceeded.
- **Fixed `analyzeMedia` Path & Retention**:
  - Fixed path validation bug: checks `users/${uid}/` instead of `uploads/${uid}/`.
  - Prevented premature deletion of user files after analysis so the knowledge vault continues to reference valid media.
- **Dead Code Cleanup**: Deleted `lib/services/decomposition_service.dart`.

---

### 4. Timezone-Aware Event Extraction & Reminders
- **Fixed Timezone Offset Bug**: The server now receives the user device's IANA timezone identifier (via `flutter_timezone`) and current local date. The model generates ISO8601 strings with explicit local offsets (e.g. `2026-10-12T14:30:00-06:00`) rather than UTC ("Z").
- **Date-Only Default**: Date-only events default to 09:00:00 local time on the target date.
- **Client Parsing & Scheduling**: Added `EventTimeParser` which parses local timestamps, schedules reminders 30 minutes prior, and automatically skips past events.
- **Unit Testing**: Added comprehensive unit tests in `test/event_time_parser_test.dart`.

---

### 5. Automated Server-Side Vault Purge & Account Deletion
- **Callable `deleteAccount`**:
  - Recursively deletes all Firestore subcollections under `users/{uid}` (`knowledge_base`, `chats` and nested `messages`, `upcoming_events`, `usage`).
  - Deletes user profile document `/users/{uid}`.
  - Deletes all Storage files under `users/{uid}/`.
  - Deletes user from Firebase Authentication via Admin SDK.
- **Local Notification Cleanup**: Cancels all pending notifications before navigating to sign-in.

---

### 6. Growth, In-App Review & Dynamic Paywall
- **Targeted Review Prompts (`in_app_review`)**:
  - Prompts only after positive moments: the 3rd auto-filed item or the first event reminder created.
  - Enforces a 90-day cooldown between requests.
  - Strictly blocked on the first app launch session.
- **Dynamic Paywall Pricing**:
  - `PaywallSheet` displays localized live prices and billing periods fetched from RevenueCat StoreProduct offerings.
  - Displays introductory offers and free trials (e.g. "Free Trial Available") when present in the App Store catalog.
  - Added "Restore Purchases" button with automated server entitlement sync.
