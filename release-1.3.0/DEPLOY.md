# Axiom 1.3.0 deployment guide

Deploy in two phases. **Phase A** is safe while 1.2.3 is still the live App Store version. **Phase B** (strict Firestore rules) waits until most users have updated to 1.3.0.

> ⚠️ **Do not deploy `firestore.rules` from this repo until Phase B.** The 1.2.3 app writes `aiUsageCount` from the device. When the new rules deny that write, 1.2.3 signs the user out ("Security breach or ghost account detected"). Until Phase B, keep the per-user rules that are live now:
>
> ```
> match /users/{userId}/{document=**} {
>   allow read, write: if request.auth != null && request.auth.uid == userId;
> }
> ```

---

## Before you start

- [ ] The project is on the **Blaze** plan (Cloud Functions and Secret Manager need it).
- [ ] **Billing is enabled on the Google Cloud project that owns the Gemini API key.** Gemini calls only count as "Paid Services" (prompts not used to improve Google's models) on a project with an active billing account. The privacy label and App Store description depend on this.
- [ ] A budget alert is set in Google Cloud → Billing → Budgets & alerts.
- [ ] Firebase CLI is up to date: `npm i -g firebase-tools`.
- [ ] Tests pass:
  ```bash
  (cd functions && npm ci && npm test)          # 17 tests, no emulator needed
  flutter analyze && flutter test
  firebase emulators:exec --only firestore,storage "cd test/rules && npm ci && npm test"
  ```

---

## Phase A: ship 1.3.0 (now)

### A1. Secrets

```bash
# A NEW Gemini key for the server. Don't reuse the key compiled into 1.2.3.
firebase functions:secrets:set GEMINI_API_KEY

# RevenueCat secret API key (Project settings → API keys → Secret, starts with sk_)
firebase functions:secrets:set REVENUECAT_SECRET_KEY

# Any long random string; paste the same value into RevenueCat in step A4
openssl rand -hex 24
firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET
```

### A2. Cloud Functions (Node 22)

```bash
cd functions && npm ci && cd ..
firebase deploy --only functions
```

The runtime is Node 22 because Google decommissioned Node 20 on 2026-10-30, so it can no longer deploy. If the CLI asks to delete functions that no longer exist in code, answer **No** unless you recognize them.

Note the URL it prints for `revenuecatWebhook`.

### A3. Storage rules

```bash
firebase deploy --only storage
```

This is safe for 1.2.3: it uses the same `users/{uid}/…` paths. Uploads must be images, audio, PDF, text, RTF or Word, up to 25 MB.

### A4. RevenueCat webhook

1. RevenueCat → Project settings → Integrations → **Webhooks** → Add.
2. URL: the `revenuecatWebhook` URL from A2.
3. Authorization header: the exact `REVENUECAT_WEBHOOK_SECRET` value.
4. Send a test event. Expect HTTP 200 `{"ok":true,"test":true}`. Test events write nothing.

Every webhook re-reads the subscriber from the RevenueCat API, so the stored tier always matches RevenueCat. Anonymous (`$RCAnonymousID…`) IDs and IDs that aren't Firebase users are ignored.

### A5. App Check

- Firebase Console → App Check → Apps → iOS: **App Attest** and **DeviceCheck** are both registered. Release builds use App Attest with a DeviceCheck fallback.
- Debug builds use the debug provider. Run once from Xcode, copy the debug token from the console log, and add it under **Manage debug tokens**.
- Every callable already has `enforceAppCheck: true`. Leave enforcement for Firestore and Storage **off** until Phase B.

### A6. Build and upload 1.3.0

```bash
flutter clean && flutter pub get
flutter build ipa --release
# Upload build/ios/ipa/*.ipa with Transporter or Xcode Organizer
```

---

## Phase B: lock down Firestore (about 2 weeks after 1.3.0 is live)

Do this when App Store Connect → Analytics shows most active devices on 1.3.0.

```bash
firebase deploy --only firestore:rules
```

These rules block client writes to the tier and quota fields, and block client deletion of `/users/{uid}` (deletion goes through the `deleteAccount` function). Users still on 1.2.3 after this will be signed out the next time the app tries to write those fields, so consider a "please update" prompt first.

Then:
- App Check → APIs: once metrics show nearly 100% verified requests, turn on **Enforce** for Cloud Firestore and Cloud Storage.
- Delete the old Gemini API key that shipped inside 1.2.3 (Google Cloud → APIs & Services → Credentials). AI features in 1.2.3 stop working at that point.

---

## Rollback

- **Functions:** redeploy the previous commit (`git checkout <prev> -- functions && firebase deploy --only functions`), or roll back a single function's revision in Cloud Run.
- **Rules:** Firebase Console → Firestore/Storage → Rules → History → pick the previous version → Publish.
- **App:** in App Store Connect, pause the phased release, or remove the build from review.
