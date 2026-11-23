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

---

## Review fixes (applied on top of the changes above)

### Blockers
- **Cloud Functions runtime:** Node 20 → **Node 22**. Google decommissioned Node 20 on 2026-10-30, so the old config couldn't deploy. Upgraded `firebase-functions` to ^7.4 and `firebase-admin` to ^14.5 (modular imports), and migrated from the deprecated `@google/generative-ai` to `@google/genai` ^3.6.
- **Free upgrade removed:** the Memory Reels upsell's "Upgrade to Infinite Brain" button wrote `accountTier` directly with no purchase. It now opens the real `PaywallSheet`.
- **Deploy order:** DEPLOY.md is now two phases. Strict Firestore rules wait until 1.3.0 adoption, because 1.2.3 signs users out when its client-side counter write is denied.
- **Embeddings:** `text-embedding-004` was shut down on 2026-01-14. Now uses `gemini-embedding-001` (768 dimensions).
- **Permanent free-tier lockout removed:** the client blocked free users after 200 lifetime AI actions, and nothing reset that count. Limits are now server-side daily counters only (UTC day).

### Server (functions/)
- **Retrieval (RAG):** chat ranks up to 300 vault items by embedding similarity plus title/keyword matches, instead of using only the 15 most recent. It always includes the 2 newest items, caps context at 8,000 characters, and backfills embeddings for older items lazily (8 per request).
- **Embeddings saved** on every analyzed item (`analyzeAsset`, `enhanceText`).
- **No arbitrary URL fetches:** `analyzeAsset`, `chatWithRag` and `analyzeMedia` accept only the caller's own Storage objects (a `users/{uid}/…` path, or a Firebase download URL resolved to one) and download them through the Admin SDK. Files are capped at 18 MB.
- **Correct MIME types:** each file's stored `contentType` is used, with the extension as fallback. `.docx` is converted to text with `mammoth`; text and RTF are sent as text; `.doc` returns a "re-save as .docx/PDF" message.
- **Quotas:** a single `TIER_CONFIG` with `upload`, `chat` and `aiops` daily limits. Every AI callable now counts against one.
- **Server-side plan checks:** `synthesizeCreation` requires Creation Engine or higher; `generateStoryboard` requires Infinite Brain.
- **RevenueCat webhook:**
  - Uses a timing-safe auth check.
  - `TEST` events return 200 without writing.
  - Ignores `$RCAnonymousID` IDs and IDs that aren't Firebase users.
  - Re-reads the subscriber from the RevenueCat API on every event, which handles expirations, both-plan cases and transfers.
- **Event extraction:** asks for local wall-clock time with no offset (DST-safe) and normalizes model output. All-day events are stored as `T09:00:00` with `allDay: true`.
- **`deleteAccount`:** uses `db.recursiveDelete()`, which has no 500-document batch limit and covers any subcollection depth.
- **`setGlobalOptions({ maxInstances: 20 })`** as a cost guard.
- **Tests:** `functions/test/` has 17 tests (helpers, plus end-to-end handler flows with in-memory fakes). Run with `npm test`.

### Rules
- Firestore: `dailyChatCount`, `lastChatDate`, `dailyAiOpsCount`, `lastAiOpsDate` and `tierSyncedAt` are now server-only. Client delete of `/users/{uid}` is blocked, since it would reset quotas. Added tests.
- Storage: allows `text/markdown`, `text/rtf` and `application/rtf`. Video stays blocked on purpose.

### App (lib/)
- App Check uses `AppleDebugProvider` in debug builds and `AppleAppAttestWithDeviceCheckFallbackProvider` in release.
- `syncEntitlements` runs at most once a day after sign-in. This corrects tiers granted by the old free-upgrade button.
- Every Storage upload sets an explicit `contentType` (new `lib/utils/mime_helper.dart`).
- The chat attachment picker is images only (no video).
- Shared text clips get `aiSummary` and are summarized and indexed with `enhanceText`, so chat can find them.
- Event parser docs and tests cover local wall time and the March 2027 DST change.

### Docs
- `DEPLOY.md`: two-phase rollout, billing prerequisite for Gemini, App Check debug tokens.
- `PRIVACY_LABEL.md`: adds Crash Data, Analytics (Device ID, Product Interaction, Coarse Location), and items to remove from the live label. Uses Apple purpose names only; corrects the Gemini data-use claim.
- `WHATS_NEW.txt`: rewritten to describe only shipped changes.
