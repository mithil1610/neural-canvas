# App Store privacy label: Axiom 1.3.0

Answers for **App Store Connect → App Privacy**, based on what the 1.3.0 code collects: the Flutter app, Cloud Functions, Firebase (Auth, Firestore, Storage, Crashlytics, Analytics, App Check), RevenueCat and the Gemini API.

## Tracking

**Does Axiom track users? No.** There is no IDFA, no App Tracking Transparency prompt, no ad SDK, and no data shared with data brokers or used for third-party advertising.

## Data collected

Use only Apple's purpose names. "Account Management" isn't one of them, so it's covered by App Functionality.

| Apple category | Data type | Linked to user | Tracking | Purposes | Where it comes from |
| --- | --- | --- | --- | --- | --- |
| Contact Info | Name | Yes | No | App Functionality | `fullName` at sign-up; optional display name |
| Contact Info | Email Address | Yes | No | App Functionality | Firebase Auth sign-in and password reset |
| User Content | Photos or Videos | Yes | No | App Functionality | Scans and shared images (photos only, no video) in the user's vault |
| User Content | Audio Data | Yes | No | App Functionality | Voice notes |
| User Content | Other User Content | Yes | No | App Functionality | Documents, pasted/shared text, chat messages, AI summaries, profile photo |
| Identifiers | User ID | Yes | No | App Functionality | Firebase UID, which is also the RevenueCat app user ID |
| Identifiers | Device ID | No | No | Analytics | Firebase Analytics app-instance ID |
| Purchases | Purchase History | Yes | No | App Functionality | Subscription status through RevenueCat / StoreKit |
| Usage Data | Product Interaction | Yes | No | App Functionality, Analytics | Daily usage counters for plan limits; Firebase Analytics events (graph tab) |
| Location | Coarse Location | No | No | Analytics | Firebase Analytics derives general location from masked IP addresses; the app never uses Location Services |
| Diagnostics | Crash Data | No | No | App Functionality | Firebase Crashlytics |

## Remove from the current label

The live 1.2.3 label lists these, but the app doesn't collect them:

- **Financial Info (payment / credit info).** Apple handles payments; the app only receives subscription status, which is covered by Purchase History.
- **Surroundings / environment scanning.**
- **"Used for advertising or marketing"** on any data type. Nothing is used that way, and the listing says so.

## Processors (for your privacy policy, not the label)

| Service | Data | Notes |
| --- | --- | --- |
| Google Firebase / Cloud | Account, vault files and text, chats, usage counters | Each user can access only their own data (Security Rules), and every API call requires App Check. |
| Google Gemini API | File contents and text sent for analysis and chat | **Only "Paid Services" when the key's Cloud project has an active billing account.** In that case Google doesn't use prompts or responses to improve its models. On unpaid quota, human reviewers may read API input and output. Enable billing before claiming "not used for AI training." |
| RevenueCat | Firebase UID, StoreKit purchase data | Subscription status only. |

## Account deletion (guideline 5.1.1(v))

Profile → **Delete Account & Purge Vault** calls the `deleteAccount` function. It deletes everything under `users/{uid}/` in Storage, the user's Firestore data at any depth (`recursiveDelete`), and the Firebase Auth account. On the device, it cancels pending notifications and logs out of RevenueCat.
