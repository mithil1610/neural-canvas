/**
 * Axiom Cloud Functions (release 1.3.0)
 *
 * Every Gemini call runs here, never on the device. All callables require
 * Firebase Auth and App Check. Quotas, plan checks and subscription tiers are
 * enforced on the server; clients cannot write those fields (see firestore.rules).
 */
const crypto = require("crypto");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { getAuth } = require("firebase-admin/auth");
const { GoogleGenAI } = require("@google/genai");
const mammoth = require("mammoth");
const H = require("./helpers");

initializeApp();
const db = getFirestore();

// Caps how far a traffic spike (or abuse) can scale each function.
setGlobalOptions({ maxInstances: 20 });

// ---------------------------------------------------------------------------
// Secrets (Secret Manager)
// ---------------------------------------------------------------------------
const geminiApiKey = defineSecret("GEMINI_API_KEY");
const revenuecatSecretKey = defineSecret("REVENUECAT_SECRET_KEY");
const revenuecatWebhookSecret = defineSecret("REVENUECAT_WEBHOOK_SECRET");

// ---------------------------------------------------------------------------
// Models and limits
// ---------------------------------------------------------------------------
const TEXT_MODEL = "gemini-2.5-flash";
const EMBED_MODEL = "gemini-embedding-001"; // text-embedding-004 was shut down on 2026-01-14
const EMBED_DIM = 768;
const MAX_INLINE_BYTES = 18 * 1024 * 1024; // Gemini inline request limit is ~20 MB

/**
 * Daily limits per plan, counted per UTC day.
 * upload: new vault items analyzed (scan, import, share, paste)
 * chat:   chat messages and Creation Engine syntheses
 * aiops:  small helper calls (titles, event extraction, embeddings, storyboards)
 */
const TIER_CONFIG = {
  "Free": { upload: 10, chat: 30, aiops: 80 },
  "Creation Engine": { upload: 100, chat: 250, aiops: 600 },
  "Infinite Brain": { upload: 1000, chat: 1000, aiops: 3000 },
};
const QUOTA_FIELDS = {
  upload: { count: "dailyUploadCount", date: "lastUploadDate", label: "upload" },
  chat: { count: "dailyChatCount", date: "lastChatDate", label: "chat" },
  aiops: { count: "dailyAiOpsCount", date: "lastAiOpsDate", label: "AI" },
};
const PAID_TIERS = ["Creation Engine", "Infinite Brain"];

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------
function requireAuth(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

function isValidId(id) {
  return typeof id === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(id);
}

/** Runs a helper that throws coded errors and rethrows them as HttpsError. */
function asHttps(fn) {
  try {
    return fn();
  } catch (e) {
    if (e && e.code) throw new HttpsError(e.code, e.message);
    throw e;
  }
}

async function getTier(uid) {
  const snap = await db.collection("users").doc(uid).get();
  return (snap.exists && snap.data().accountTier) || "Free";
}

async function requireTier(uid, allowed, featureName) {
  const tier = await getTier(uid);
  if (!allowed.includes(tier)) {
    throw new HttpsError(
      "permission-denied",
      `${featureName} is part of the ${allowed[0]} plan. Upgrade to unlock it.`
    );
  }
  return tier;
}

/** Atomically checks and increments one daily counter. Returns the caller's tier. */
async function enforceQuota(uid, kind) {
  const f = QUOTA_FIELDS[kind];
  const userRef = db.collection("users").doc(uid);
  const today = H.utcDay();
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.exists ? snap.data() : {};
    const tier = TIER_CONFIG[data.accountTier] ? data.accountTier : "Free";
    const limit = TIER_CONFIG[tier][kind];
    const used = data[f.date] === today ? data[f.count] || 0 : 0;
    if (used >= limit) {
      throw new HttpsError(
        "resource-exhausted",
        `You've reached today's ${f.label} limit (${limit}) on the ${tier} plan. ` +
          (tier === "Infinite Brain" ? "It resets tomorrow." : "It resets tomorrow, or upgrade for more.")
      );
    }
    tx.set(
      userRef,
      {
        [f.count]: used + 1,
        [f.date]: today,
        aiUsageCount: FieldValue.increment(1), // lifetime analytics only; never used as a limit
      },
      { merge: true }
    );
    return tier;
  });
}

// --- Gemini (Google Gen AI SDK) ---------------------------------------------
let _ai = null;
function ai() {
  if (!_ai) _ai = new GoogleGenAI({ apiKey: geminiApiKey.value() });
  return _ai;
}

async function generate({ parts, contents, json = false, system } = {}) {
  const config = {};
  if (json) config.responseMimeType = "application/json";
  if (system) config.systemInstruction = system;
  const res = await ai().models.generateContent({
    model: TEXT_MODEL,
    contents: contents || [{ role: "user", parts }],
    config,
  });
  return (res && res.text) || "";
}

async function safeEmbed(text) {
  const t = String(text || "").trim();
  if (!t) return null;
  try {
    const res = await ai().models.embedContent({
      model: EMBED_MODEL,
      contents: t.slice(0, 8000),
      config: { outputDimensionality: EMBED_DIM },
    });
    const v = res && res.embeddings && res.embeddings[0] && res.embeddings[0].values;
    return Array.isArray(v) && v.length ? v : null;
  } catch (e) {
    console.warn("Embedding failed:", e.message || e);
    return null;
  }
}

// --- Storage ----------------------------------------------------------------
async function loadUserFile(path) {
  const file = getStorage().bucket().file(path);
  let meta;
  try {
    [meta] = await file.getMetadata();
  } catch (e) {
    throw new HttpsError("not-found", "The file could not be found.");
  }
  if (Number(meta.size || 0) > MAX_INLINE_BYTES) {
    throw new HttpsError("failed-precondition", "This file is too large to analyze (max 18 MB).");
  }
  const [buffer] = await file.download();
  return { buffer, contentType: meta.contentType || "" };
}

/** Turns a file into Gemini parts. Returns null for formats Gemini can't read. */
async function fileToParts(buffer, mime, kind) {
  if (kind === "docx") {
    const { value } = await mammoth.extractRawText({ buffer });
    return [{ text: `DOCUMENT TEXT:\n${String(value || "").slice(0, 120000)}` }];
  }
  if (kind === "text") {
    return [{ text: `DOCUMENT TEXT:\n${buffer.toString("utf8").slice(0, 120000)}` }];
  }
  if (["image", "audio", "video", "pdf"].includes(kind)) {
    return [{ inlineData: { mimeType: mime, data: buffer.toString("base64") } }];
  }
  return null;
}

const ANALYSIS_BASE = `You are an expert data extraction engine for a personal Second Brain app.
Analyze the provided asset. If the input is a standard document or scene, provide a concise smartTitle and a detailed summary as instructed.

CRITICAL CONVERSATION OVERRIDE: If the input image is identified as a chat message thread, direct message log, or a tall rolling screenshot from applications like WhatsApp, iMessage, Telegram, Slack, or Discord:
1. Bypass standard paragraph summaries.
2. Transcribe the entire conversation thread chronologically from top to bottom.
3. Format the 'summary' output field strictly as a clean, highly readable dialogue script using markdown bolding for names:
   **[Sender/Left Side]**: Message text here
   **[Receiver/Right Side]**: Response text here
4. Generate a 'smartTitle' that summarizes the core relationship or outcome of that specific discussion thread.
`;
const ANALYSIS_BY_KIND = {
  pdf: "Extract all textual data via deep OCR. Identify core concepts, critical names, dates, data points, entities, and provide an exhaustive analytical summary.",
  docx: "Read the document text. Identify core concepts, critical names, dates, data points, entities, and provide an exhaustive analytical summary.",
  text: "Read the text. Identify core concepts, critical names, dates, data points, entities, and provide a thorough summary.",
  audio: "Listen to this audio track carefully. Transcribe the spoken text entirely, summarize the core topics discussed, and output key takeaways and any decisions, dates or owners mentioned.",
  video: "Watch this video clip sequentially. Detect key scenes, summarize visual actions, transcribe background audio, and create a timeline summary of what occurs.",
  image: "Perform an image analysis. Read any text via OCR (keep exact names, numbers, dates, times, addresses and passwords), detect visible objects and actions, and summarize the overall context.",
};
function analysisPrompt(kind) {
  return (
    ANALYSIS_BASE +
    (ANALYSIS_BY_KIND[kind] || ANALYSIS_BY_KIND.image) +
    `\nRespond strictly as JSON: { "title": "...", "summary": "...", "category": "..." }. ` +
    `For category choose exactly one of: [${H.ALLOWED_CATEGORIES.join(", ")}].`
  );
}

async function saveSummaryAndEmbedding(docRef, fields, title, summary) {
  const update = { ...fields, analyzedAt: FieldValue.serverTimestamp() };
  const emb = await safeEmbed(`${title}\n${summary}`);
  if (emb) {
    update.embedding = emb;
    update.embeddingModel = EMBED_MODEL;
  }
  await docRef.set(update, { merge: true });
}

// --- Retrieval (chat RAG) ---------------------------------------------------
async function retrieveContext(uid, question) {
  const snap = await db
    .collection("users").doc(uid).collection("knowledge_base")
    .orderBy("uploadedAt", "desc")
    .limit(300)
    .select("smartTitle", "fileName", "title", "aiSummary", "content", "embedding", "uploadedAt")
    .get();

  const items = snap.docs.map((d, i) => {
    const data = d.data();
    const summary =
      data.aiSummary && !/^Processing\b.*\.\.\.$/.test(data.aiSummary) ? data.aiSummary : data.content || "";
    const ts = data.uploadedAt && data.uploadedAt.toDate ? data.uploadedAt.toDate() : null;
    return {
      id: d.id,
      ref: d.ref,
      title: data.smartTitle || data.fileName || data.title || "Untitled",
      summary: String(summary || ""),
      embedding: Array.isArray(data.embedding) && data.embedding.length === EMBED_DIM ? data.embedding : null,
      recency: i,
      date: ts ? ts.toISOString().slice(0, 10) : "",
    };
  });

  // Lazily backfill embeddings for items saved before 1.3.0 (a few per request).
  const missing = items.filter((it) => !it.embedding && it.summary).slice(0, 8);
  await Promise.all(
    missing.map(async (it) => {
      const e = await safeEmbed(`${it.title}\n${it.summary}`);
      if (e) {
        it.embedding = e;
        await it.ref.set({ embedding: e, embeddingModel: EMBED_MODEL }, { merge: true }).catch(() => {});
      }
    })
  );

  const qEmb = question ? await safeEmbed(question) : null;
  const ranked = H.rankItems(items, question, qEmb, 12);
  const newest = items.slice(0, 2).filter((n) => !ranked.some((r) => r.id === n.id));
  return H.buildContext([...ranked, ...newest], 8000, 900);
}

// ============================================================================
// SUBSCRIPTIONS (RevenueCat)
// ============================================================================
async function fetchRevenueCatTier(appUserId) {
  const res = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`, {
    headers: { Authorization: `Bearer ${revenuecatSecretKey.value()}`, "Content-Type": "application/json" },
  });
  if (!res.ok) throw new Error(`RevenueCat API returned ${res.status}`);
  const data = await res.json();
  return H.tierFromEntitlements((data.subscriber && data.subscriber.entitlements) || {});
}

async function writeTier(uid, tier) {
  await db.collection("users").doc(uid).set(
    { accountTier: tier, tierSyncedAt: FieldValue.serverTimestamp() },
    { merge: true }
  );
}

function safeEqual(a, b) {
  const x = Buffer.from(String(a || ""));
  const y = Buffer.from(String(b || ""));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

/**
 * RevenueCat webhook. Every event re-reads the subscriber's current entitlements from
 * the RevenueCat API instead of inferring the tier from the event type, so expirations,
 * upgrades, refunds and transfers all end in the right state.
 */
exports.revenuecatWebhook = onRequest(
  { secrets: [revenuecatWebhookSecret, revenuecatSecretKey] },
  async (req, res) => {
    if (req.method !== "POST") return res.status(405).send("Method Not Allowed");

    const expected = revenuecatWebhookSecret.value();
    const got = req.get("authorization") || "";
    if (!safeEqual(got, expected) && !safeEqual(got, `Bearer ${expected}`)) {
      console.warn("RevenueCat webhook: unauthorized.");
      return res.status(401).send("Unauthorized");
    }

    const event = (req.body && req.body.event) || null;
    if (!event) return res.status(400).send("Missing event.");
    if (event.type === "TEST") return res.status(200).json({ ok: true, test: true });

    const ids = new Set(
      [
        event.app_user_id,
        event.original_app_user_id,
        ...(Array.isArray(event.aliases) ? event.aliases : []),
        ...(Array.isArray(event.transferred_from) ? event.transferred_from : []),
        ...(Array.isArray(event.transferred_to) ? event.transferred_to : []),
      ].filter((id) => typeof id === "string" && id && !H.isAnonymousRcId(id) && !id.includes("/"))
    );

    try {
      let updated = 0;
      for (const id of ids) {
        try {
          await getAuth().getUser(id); // only real Firebase users get a profile doc
        } catch (_) {
          continue;
        }
        await writeTier(id, await fetchRevenueCatTier(id));
        updated++;
      }
      return res.status(200).json({ ok: true, updated });
    } catch (err) {
      console.error("RevenueCat webhook failed:", err);
      return res.status(500).send("Internal Server Error"); // RevenueCat retries on 5xx
    }
  }
);

/** Re-reads the caller's subscription from RevenueCat and stores the tier. */
exports.syncEntitlements = onCall(
  { enforceAppCheck: true, secrets: [revenuecatSecretKey] },
  async (request) => {
    const uid = requireAuth(request);
    try {
      const tier = await fetchRevenueCatTier(uid);
      await writeTier(uid, tier);
      return { accountTier: tier };
    } catch (err) {
      console.error("syncEntitlements failed:", err);
      throw new HttpsError("internal", "Could not sync subscription status.");
    }
  }
);

// ============================================================================
// AI FEATURES
// ============================================================================

/** Analyzes a vault file: title, summary, category and embedding. */
exports.analyzeAsset = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey], timeoutSeconds: 180, memory: "1GiB" },
  async (request) => {
    const uid = requireAuth(request);
    const { docId, fileUrl, storagePath, fileType } = request.data || {};
    if (!isValidId(docId)) throw new HttpsError("invalid-argument", "Missing or invalid docId.");
    const path = asHttps(() => H.resolveUserStoragePath(uid, { storagePath, fileUrl }));

    await enforceQuota(uid, "upload");

    let title = "Note";
    let summary = "";
    let category = "documents";
    try {
      const { buffer, contentType } = await loadUserFile(path);
      const mime = H.resolveMime(contentType, path, fileType);
      const kind = H.mediaKind(mime);
      const parts = await fileToParts(buffer, mime, kind);
      if (!parts) {
        title = "Unsupported file";
        summary =
          kind === "doc"
            ? "Older Word (.doc) files can't be analyzed yet. Re-save it as .docx or PDF and add it again."
            : "This file type can't be analyzed yet. Try a photo, PDF, Word (.docx), text or audio file.";
      } else {
        const raw = await generate({ parts: [...parts, { text: analysisPrompt(kind) }], json: true });
        const parsed = H.parseJsonLoose(raw) || {};
        title = String(parsed.title || "").trim().slice(0, 120) || "Note";
        summary = String(parsed.summary || raw || "").trim();
        category = H.normalizeCategory(parsed.category);
      }
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("analyzeAsset failed:", err);
      throw new HttpsError("internal", "Failed to analyze this file.");
    }

    const docRef = db.collection("users").doc(uid).collection("knowledge_base").doc(docId);
    await saveSummaryAndEmbedding(docRef, { smartTitle: title, aiSummary: summary, category }, title, summary);
    return { title, summary, category };
  }
);

/**
 * Finds dated events in a summary. Times come back as LOCAL wall-clock time with no
 * offset ("YYYY-MM-DDTHH:MM:SS", or "YYYY-MM-DD" when no time is given); the app reads
 * them in the device's time zone, which also keeps daylight-saving changes correct.
 */
exports.extractEvents = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey] },
  async (request) => {
    const uid = requireAuth(request);
    const { docId, summaryText, timezone, currentDate } = request.data || {};
    if (typeof summaryText !== "string" || !summaryText.trim()) return { events: [] };

    const tz = typeof timezone === "string" && /^[A-Za-z0-9_+\-/]{1,64}$/.test(timezone) ? timezone : "UTC";
    const today = typeof currentDate === "string" && /^\d{4}-\d{2}-\d{2}$/.test(currentDate) ? currentDate : H.utcDay();

    await enforceQuota(uid, "aiops");

    const prompt = `Find scheduled events in the text below (appointments, meetings, deadlines, reservations, parties, flights).
The user's time zone is ${tz}. Today's date for the user is ${today}.

Rules:
1. Resolve relative dates ("tomorrow", "this Friday", "next Monday") against ${today}.
2. "eventDateTime" is the LOCAL wall-clock time as written, with NO time zone offset and NO "Z":
   "YYYY-MM-DDTHH:MM:SS" when a time is given, or "YYYY-MM-DD" when only a date is given.
3. If the year is missing, use the next occurrence on or after ${today}.
4. Skip anything that is not a specific date.
Return a JSON array of objects with string keys "eventTitle", "eventDateTime", "eventLocation" (empty string if unknown). Return [] if none.

Text:
${summaryText.slice(0, 20000)}`;

    let events = [];
    try {
      const parsed = H.parseJsonLoose(await generate({ parts: [{ text: prompt }], json: true }));
      events = (Array.isArray(parsed) ? parsed : [])
        .slice(0, 10)
        .map((ev) => ({
          eventTitle: String((ev && ev.eventTitle) || "Upcoming Event").slice(0, 120),
          eventDateTime: H.normalizeEventDateTime(ev && ev.eventDateTime),
          eventLocation: String((ev && ev.eventLocation) || "").slice(0, 200),
        }))
        .filter((ev) => ev.eventDateTime !== "TBD");
    } catch (err) {
      console.error("extractEvents failed:", err);
      throw new HttpsError("internal", "Failed to extract events.");
    }

    if (events.length) {
      const batch = db.batch();
      const col = db.collection("users").doc(uid).collection("upcoming_events");
      for (const ev of events) {
        const allDay = ev.eventDateTime.length === 10;
        batch.set(col.doc(), {
          sourceDocId: isValidId(docId) ? docId : "",
          eventTitle: ev.eventTitle,
          // Stored as a sortable local time string; all-day events sort at 09:00.
          eventDateTime: allDay ? `${ev.eventDateTime}T09:00:00` : ev.eventDateTime,
          allDay,
          eventLocation: ev.eventLocation || "TBD",
          timezone: tz,
          createdAt: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    return { events };
  }
);

/** Chat with the vault: retrieval over the user's items, then a grounded answer. */
exports.chatWithRag = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey], timeoutSeconds: 120, memory: "1GiB" },
  async (request) => {
    const uid = requireAuth(request);
    const { prompt, chatId, mediaUrl, mediaStoragePath, fileName, messageType } = request.data || {};
    const question = typeof prompt === "string" ? prompt.trim().slice(0, 4000) : "";
    const hasMedia = !!(mediaUrl || mediaStoragePath);
    if (!question && !hasMedia) throw new HttpsError("invalid-argument", "Missing prompt or media.");
    if (chatId !== undefined && chatId !== null && !isValidId(chatId)) {
      throw new HttpsError("invalid-argument", "Invalid chatId.");
    }

    await enforceQuota(uid, "chat");

    const chats = db.collection("users").doc(uid).collection("chats");
    const chatRef = chatId ? chats.doc(chatId) : chats.doc();
    const messages = chatRef.collection("messages");

    // Validate and load any attachment before writing anything.
    let mediaParts = [];
    let mediaPath = null;
    if (hasMedia) {
      mediaPath = asHttps(() => H.resolveUserStoragePath(uid, { storagePath: mediaStoragePath, fileUrl: mediaUrl }));
      const { buffer, contentType } = await loadUserFile(mediaPath);
      const mime = H.resolveMime(contentType, mediaPath);
      mediaParts = (await fileToParts(buffer, mime, H.mediaKind(mime))) || [];
    }

    const [context, historySnap] = await Promise.all([
      retrieveContext(uid, question),
      messages.orderBy("timestamp", "desc").limit(6).get(),
    ]);

    const userMsg = {
      senderId: uid,
      role: "user",
      timestamp: FieldValue.serverTimestamp(),
      type: messageType === "mixed" || messageType === "image" ? messageType : hasMedia ? "mixed" : "text",
      content: question || mediaUrl || "",
    };
    if (hasMedia) {
      if (mediaUrl) userMsg.mediaUrl = mediaUrl;
      userMsg.fileName = typeof fileName === "string" ? fileName.slice(0, 200) : "";
    }
    await chatRef.set({ updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    await messages.add(userMsg);

    const contents = [];
    for (const d of historySnap.docs.reverse()) {
      const m = d.data();
      const text = String(m.content || "");
      if (!text || text.startsWith("https://firebasestorage.googleapis.com")) continue;
      contents.push({ role: m.role === "ai" || m.role === "assistant" || m.role === "model" ? "model" : "user", parts: [{ text }] });
    }
    const system =
      "You are Axiom, the user's private AI second brain. Answer from the vault items provided when they are relevant, " +
      "and say plainly when the vault doesn't contain the answer instead of guessing. Keep answers short and specific; " +
      "include exact names, numbers, dates and passwords from the vault when asked.";
    contents.push({
      role: "user",
      parts: [
        { text: `VAULT ITEMS:\n${context || "(no items saved yet)"}\n\nQUESTION:\n${question || "Describe the attached file."}` },
        ...mediaParts,
      ],
    });

    let answer;
    try {
      answer = (await generate({ contents, system })).trim() || "I couldn't come up with an answer for that.";
    } catch (err) {
      console.error("chatWithRag generation failed:", err);
      throw new HttpsError("internal", "Failed to generate a chat response.");
    }

    await messages.add({
      senderId: "system",
      role: "ai",
      timestamp: FieldValue.serverTimestamp(),
      type: "text",
      content: answer,
    });
    return { response: answer, chatId: chatRef.id };
  }
);

/** Creation Engine: writes something new from the user's vault. Paid plans only. */
exports.synthesizeCreation = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey], timeoutSeconds: 120 },
  async (request) => {
    const uid = requireAuth(request);
    const prompt = typeof (request.data || {}).prompt === "string" ? request.data.prompt.trim().slice(0, 4000) : "";
    if (!prompt) throw new HttpsError("invalid-argument", "Missing prompt.");

    await requireTier(uid, PAID_TIERS, "AI Generation");
    await enforceQuota(uid, "chat");

    const context = await retrieveContext(uid, prompt);
    const text = `You are the Axiom Creation Engine. Using only the user's vault items below as source material, fulfill this request: ${prompt}
Write an engaging, well-structured result in clean markdown.

VAULT ITEMS:
${context || "(empty vault)"}`;
    try {
      return { content: await generate({ parts: [{ text }] }) };
    } catch (err) {
      console.error("synthesizeCreation failed:", err);
      throw new HttpsError("internal", "Failed to generate content.");
    }
  }
);

/** Memory Reel storyboard. Infinite Brain only. */
exports.generateStoryboard = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey], timeoutSeconds: 120 },
  async (request) => {
    const uid = requireAuth(request);
    const { summaries, dateKey } = request.data || {};
    if (!Array.isArray(summaries) || summaries.length === 0) {
      throw new HttpsError("invalid-argument", "Missing summaries array.");
    }
    await requireTier(uid, ["Infinite Brain"], "Memory Reels");
    await enforceQuota(uid, "aiops");

    const clipped = summaries.slice(0, 30).map((s) => String(s).slice(0, 2000));
    const prompt = `Act as a Master Short-Form Director. Analyze these media segment summaries representing a cluster of memories (${String(dateKey || "").slice(0, 40)}).
Synthesize a chronological video narrative story arc script layout.
Generate subtitle text overlays for every slide/scene transition and suggest an overarching theme vibe or musical tempo.
Package everything as markdown using ## headers, bullet points, and blockquotes.

Summaries:
${clipped.join("\n\n---\n\n")}`;
    try {
      return { storyboard: await generate({ parts: [{ text: prompt }] }) };
    } catch (err) {
      console.error("generateStoryboard failed:", err);
      throw new HttpsError("internal", "Failed to generate storyboard.");
    }
  }
);

/** 3–4 word title for pasted text. Never throws for model errors. */
exports.generateTitle = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey] },
  async (request) => {
    const uid = requireAuth(request);
    const text = typeof (request.data || {}).text === "string" ? request.data.text : "";
    if (!text.trim()) return { title: "Untitled Note" };
    await enforceQuota(uid, "aiops");
    const prompt = `Write a descriptive 3-to-4 word title for this text. Return only the title, with no quotes or punctuation.\n\nText: ${text.slice(0, 500)}`;
    try {
      const title = (await generate({ parts: [{ text: prompt }] })).replace(/["*\n]/g, " ").trim().slice(0, 80);
      return { title: title || "Untitled Note" };
    } catch (err) {
      console.error("generateTitle failed:", err);
      return { title: "Untitled Note" };
    }
  }
);

/** Summarizes pasted or shared text into a vault item and indexes it for chat. */
exports.enhanceText = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey] },
  async (request) => {
    const uid = requireAuth(request);
    const { docId, rawText } = request.data || {};
    if (!isValidId(docId) || typeof rawText !== "string" || !rawText.trim()) {
      throw new HttpsError("invalid-argument", "Missing docId or rawText.");
    }
    await enforceQuota(uid, "upload");

    const source = rawText.slice(0, 50000);
    const prompt = `Rewrite this note as a clear, structured summary. Keep every name, number, date, time, address, link and password exactly as written. Return only the summary.\n\nText: ${source}`;
    let summary = source;
    try {
      summary = (await generate({ parts: [{ text: prompt }] })).trim() || source;
    } catch (err) {
      console.error("enhanceText generation failed (keeping raw text):", err);
    }
    const docRef = db.collection("users").doc(uid).collection("knowledge_base").doc(docId);
    const snap = await docRef.get();
    const title = (snap.exists && (snap.data().smartTitle || snap.data().fileName || snap.data().title)) || "Note";
    await saveSummaryAndEmbedding(docRef, { aiSummary: summary }, title, summary);
    return { summary };
  }
);

/** Embedding for a search query (same model and size as stored vault embeddings). */
exports.getEmbedding = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey] },
  async (request) => {
    const uid = requireAuth(request);
    const query = typeof (request.data || {}).query === "string" ? request.data.query : "";
    if (!query.trim()) return { embedding: [] };
    await enforceQuota(uid, "aiops");
    const emb = await safeEmbed(query);
    if (!emb) throw new HttpsError("internal", "Failed to generate embedding.");
    return { embedding: emb };
  }
);

/** Auto-titles a chat from its first messages. Never throws for model errors. */
exports.updateChatTitle = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey] },
  async (request) => {
    const uid = requireAuth(request);
    const { chatId } = request.data || {};
    if (!isValidId(chatId)) throw new HttpsError("invalid-argument", "Missing chatId.");
    await enforceQuota(uid, "aiops");

    const chatRef = db.collection("users").doc(uid).collection("chats").doc(chatId);
    const snap = await chatRef.collection("messages").orderBy("timestamp", "asc").limit(2).get();
    const opening = snap.docs
      .map((d) => `${d.data().role === "ai" ? "AI" : "User"}: ${String(d.data().content || "").slice(0, 500)}`)
      .join("\n");
    const prompt = `Write a descriptive 3-to-4 word title for this conversation. Return only the title, with no quotes or punctuation.\n\n${opening}`;
    try {
      const title = (await generate({ parts: [{ text: prompt }] })).replace(/["*\n]/g, " ").trim().slice(0, 80) || "New Conversation";
      await chatRef.set({ title }, { merge: true });
      return { title };
    } catch (err) {
      console.error("updateChatTitle failed:", err);
      return { title: "New Conversation" };
    }
  }
);

/** Legacy callable kept for older builds. Only reads the caller's own files. */
exports.analyzeMedia = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey], timeoutSeconds: 120, memory: "1GiB" },
  async (request) => {
    const uid = requireAuth(request);
    const { prompt, mediaPath } = request.data || {};
    if (typeof prompt !== "string" || !prompt.trim()) {
      throw new HttpsError("invalid-argument", "Missing 'prompt' in request.");
    }
    await enforceQuota(uid, "upload");

    const parts = [{ text: prompt.slice(0, 8000) }];
    if (mediaPath) {
      const path = asHttps(() => H.resolveUserStoragePath(uid, { storagePath: mediaPath }));
      const { buffer, contentType } = await loadUserFile(path);
      const mime = H.resolveMime(contentType, path);
      parts.push(...((await fileToParts(buffer, mime, H.mediaKind(mime))) || []));
    }
    try {
      return { response: await generate({ parts, system: "You are Axiom, a personal digital memory assistant." }) };
    } catch (err) {
      console.error("analyzeMedia failed:", err);
      throw new HttpsError("internal", "Failed to analyze media.");
    }
  }
);

// ============================================================================
// ACCOUNT DELETION ("Automated Purge Vault")
// ============================================================================
exports.deleteAccount = onCall(
  { enforceAppCheck: true, timeoutSeconds: 300, memory: "512MiB" },
  async (request) => {
    const uid = requireAuth(request);
    console.log(`Starting account purge for ${uid}`);
    try {
      try {
        await getStorage().bucket().deleteFiles({ prefix: `users/${uid}/` });
      } catch (e) {
        console.warn("Storage purge warning (continuing):", e.message || e);
      }
      // Deletes the profile and every subcollection at any depth, with no 500-write batch limit.
      await db.recursiveDelete(db.collection("users").doc(uid));
      await getAuth().deleteUser(uid);
      return { success: true };
    } catch (err) {
      console.error(`Account purge failed for ${uid}:`, err);
      throw new HttpsError("internal", "Account deletion encountered an issue. Please try again.");
    }
  }
);
