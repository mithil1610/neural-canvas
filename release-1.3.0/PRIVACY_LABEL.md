# App Store Privacy Nutrition Label – Axiom (Version 1.3.0)

This document provides a complete audit of every data type collected and processed by **Axiom – Your AI Second Brain** based directly on code inspection of the Flutter client (`lib/`), Cloud Functions (`functions/`), Firestore Security Rules (`firestore.rules`), and Cloud Storage (`storage.rules`).

Use this guide to configure the **App Privacy** section in **App Store Connect**.

---

## Executive Summary: Tracking & Advertising

> **DOES THIS APP TRACK USERS?**  
> **NO.** The app does **NOT** track users across third-party apps or websites for targeted advertising or data-broker profiling. It does **NOT** use IDFA, App Tracking Transparency (ATT), or third-party ad networks (no AdMob, Meta Audience Network, Unity Ads, etc.).

> **IS ANY DATA USED FOR THIRD-PARTY ADVERTISING?**  
> **NO.** No user data, files, chats, or identifiers are sold or shared with advertisers or third-party advertising partners.

---

## Data Types Collected & App Store Label Breakdown

| Data Category | Specific Data Type | Collected? | Linked to User? | Used for Tracking? | Primary Purpose(s) | Notes & Code References |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **Contact Info** | **Email Address** | Yes | **Yes** | No | • App Functionality<br>• Account Management | Used by Firebase Authentication (`lib/services/auth_service.dart`) for user sign-in and password recovery. |
| **Contact Info** | **Name** (Display Name) | Yes | **Yes** | No | • App Functionality | Optional user display name stored in Firebase Auth profile (`auth_service.dart`). |
| **User Content** | **Photos or Videos** | Yes | **Yes** | No | • App Functionality | Uploaded by user to personal vault (`users/{uid}/uploads/` in Cloud Storage and Firestore `knowledge_base`). Analyzed by server-side Gemini Cloud Functions. |
| **User Content** | **Audio Data** | Yes | **Yes** | No | • App Functionality | User voice memos and audio recordings uploaded to `users/{uid}/uploads/` for automated transcription and filing. |
| **User Content** | **Customer Support / Chat History** | Yes | **Yes** | No | • App Functionality | Chat queries and AI responses stored under `users/{uid}/chats/{chatId}/messages/` in Firestore for conversation continuity and RAG context. |
| **User Content** | **Other User Content** (Notes, Docs, PDFs) | Yes | **Yes** | No | • App Functionality | Scanned documents, PDFs, Word docs, text clips uploaded to personal vault for semantic search, vector indexing, and AI synthesis. |
| **Purchases** | **Purchase History** | Yes | **Yes** | No | • App Functionality | Subscription status and transaction identifiers managed via Apple In-App Purchase and RevenueCat (`purchases_flutter`). Maps to `accountTier` ("Free", "Creation Engine", "Infinite Brain"). |
| **Identifiers** | **User ID** | Yes | **Yes** | No | • App Functionality | Firebase Auth UID and RevenueCat App User ID (`Purchases.logIn(uid)`). Used strictly to isolate vault storage and enforce server-side security rules. |
| **Identifiers** | **Device / OS Timezone** | Yes | **Yes** | No | • App Functionality | Local IANA timezone (e.g. `America/Chicago`) retrieved via `flutter_timezone` and sent to `extractEvents` Cloud Function solely to compute accurate local calendar notifications. |
| **Usage Data** | **Product Interaction** | Yes | **Yes** | No | • App Functionality | Daily upload counter (`dailyUploadCount`), AI interaction counter (`aiUsageCount`), and `lastUploadDate` stored in `users/{uid}` to enforce server-side subscription quotas. In-app review prompt milestones (e.g. 3rd capture or 1st reminder) stored locally via `shared_preferences`. |
| **Diagnostics** | **Crash & Performance Data** | Optional | **No** | No | • Analytics | Standard Firebase Crashlytics / Performance logs (if enabled in project) for debugging crash reports. |

---

## Detailed Data Usage Answers for App Store Connect

When completing the App Privacy questionnaire in App Store Connect, provide the following responses:

### 1. Contact Information
* **Email Address**:
  * **Collected**: Yes
  * **Linked to User**: Yes
  * **Used for Tracking**: No
  * **Purposes**: App Functionality, Account Management
* **Name**:
  * **Collected**: Yes
  * **Linked to User**: Yes
  * **Used for Tracking**: No
  * **Purposes**: App Functionality

### 2. User Content
* **Photos or Videos**:
  * **Collected**: Yes
  * **Linked to User**: Yes
  * **Used for Tracking**: No
  * **Purposes**: App Functionality (vault storage and AI analysis)
* **Audio Data**:
  * **Collected**: Yes
  * **Linked to User**: Yes
  * **Used for Tracking**: No
  * **Purposes**: App Functionality (voice note transcription and analysis)
* **Other User Content (Documents, Text, Notes, Chat Messages)**:
  * **Collected**: Yes
  * **Linked to User**: Yes
  * **Used for Tracking**: No
  * **Purposes**: App Functionality (retrieval-augmented generation, knowledge base storage)

### 3. Purchases
* **Purchase History**:
  * **Collected**: Yes
  * **Linked to User**: Yes
  * **Used for Tracking**: No
  * **Purposes**: App Functionality (unlocking Creation Engine / Infinite Brain features)

### 4. Identifiers
* **User ID**:
  * **Collected**: Yes
  * **Linked to User**: Yes
  * **Used for Tracking**: No
  * **Purposes**: App Functionality (authenticating requests and data ownership)

### 5. Usage Data
* **Product Interaction**:
  * **Collected**: Yes
  * **Linked to User**: Yes
  * **Used for Tracking**: No
  * **Purposes**: App Functionality (quota limits and in-app review prompting)

---

## Third-Party Sub-Processors & Data Flow

| Service | Data Handled | Location / Purpose | Security Safeguards |
| :--- | :--- | :--- | :--- |
| **Google Cloud / Firebase** | Auth credentials, Firestore databases, Cloud Storage assets | Cloud hosting, user authentication, isolated storage (`users/{uid}/**`). | Security Rules enforced at database & storage layers. App Check enforced on all Cloud Functions. |
| **Google Gemini API** | Content text and uploaded files for analysis, RAG chat, event extraction | Ephemeral processing for AI inferences. Keys secured in Secret Manager; client has no direct access. | Data not retained for training under Google Cloud Vertex / enterprise Gemini API terms. |
| **RevenueCat** | StoreKit transaction receipts, Firebase UID | Subscription entitlement management. | Verified server-side webhooks with shared authorization secret. |

---

## Data Deletion & Privacy Rights ("Automated Purge Vault")

Axiom 1.3.0 implements complete, verified, server-side data purging compliant with Apple App Store Review Guideline 5.1.1(v) and GDPR/CCPA "Right to Erasure":
1. **Cloud Storage**: Recursively purges all user objects under `users/{uid}/`.
2. **Firestore Collections**: Recursively deletes `users/{uid}/knowledge_base/`, `users/{uid}/chats/` (and subcollection `messages/`), `users/{uid}/upcoming_events/`, and `users/{uid}/usage/`.
3. **Firestore User Document**: Deletes `/users/{uid}`.
4. **Firebase Authentication**: Deletes the Firebase Auth user record via Admin SDK.
5. **Local Device**: Cancels all pending notifications (`flutterLocalNotificationsPlugin.cancelAll()`) and signs out of RevenueCat (`Purchases.logOut()`).
