const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");

admin.initializeApp();
const db = admin.firestore();

// Secret definitions for Secret Manager
const geminiApiKey = defineSecret("GEMINI_API_KEY");
const revenuecatSecretKey = defineSecret("REVENUECAT_SECRET_KEY");
const revenuecatWebhookSecret = defineSecret("REVENUECAT_WEBHOOK_SECRET");

// Centralized Tier Quota Configuration
const TIER_CONFIG = {
  "Free": {
    dailyUploads: 10,
    dailyChats: 30,
    monthlyAI: 200,
  },
  "Creation Engine": {
    dailyUploads: 100,
    dailyChats: 250,
    monthlyAI: 750,
  },
  "Infinite Brain": {
    dailyUploads: 1000,
    dailyChats: 1000,
    monthlyAI: 3000,
  },
};

/**
 * Helper to get Gemini client with the secret API key
 */
function getGenAI() {
  const key = geminiApiKey.value();
  return new GoogleGenerativeAI(key);
}

/**
 * Atomically checks and updates quota within a Firestore transaction.
 * @param {string} uid User ID
 * @param {'upload' | 'chat'} actionType Action type
 * @returns {Promise<{accountTier: string}>}
 */
async function enforceQuotaTransaction(uid, actionType) {
  const userRef = db.collection("users").doc(uid);
  const today = new Date().toISOString().split("T")[0];

  return await db.runTransaction(async (transaction) => {
    const userDoc = await transaction.get(userRef);
    const data = userDoc.exists ? userDoc.data() : {};

    const accountTier = data.accountTier || "Free";
    const limits = TIER_CONFIG[accountTier] || TIER_CONFIG["Free"];

    let dailyUploadCount = data.dailyUploadCount || 0;
    let dailyChatCount = data.dailyChatCount || 0;
    const lastUploadDate = data.lastUploadDate || "";
    const lastChatDate = data.lastChatDate || "";

    if (actionType === "upload") {
      if (lastUploadDate !== today) {
        dailyUploadCount = 0;
      }
      if (dailyUploadCount >= limits.dailyUploads) {
        throw new HttpsError(
          "resource-exhausted",
          `Daily upload limit reached (${dailyUploadCount}/${limits.dailyUploads}) for ${accountTier} tier. Upgrade your plan to increase limits.`
        );
      }
      dailyUploadCount += 1;
      transaction.set(
        userRef,
        {
          dailyUploadCount,
          lastUploadDate: today,
          aiUsageCount: admin.firestore.FieldValue.increment(1),
        },
        { merge: true }
      );
    } else if (actionType === "chat") {
      if (lastChatDate !== today) {
        dailyChatCount = 0;
      }
      if (dailyChatCount >= limits.dailyChats) {
        throw new HttpsError(
          "resource-exhausted",
          `Daily chat limit reached (${dailyChatCount}/${limits.dailyChats}) for ${accountTier} tier. Upgrade your plan for more conversation capacity.`
        );
      }
      dailyChatCount += 1;
      transaction.set(
        userRef,
        {
          dailyChatCount,
          lastChatDate: today,
          aiUsageCount: admin.firestore.FieldValue.increment(1),
        },
        { merge: true }
      );
    }

    return { accountTier };
  });
}

// ============================================================================
// TASK 2: REVENUECAT WEBHOOK & ENTITLEMENT SYNC
// ============================================================================

/**
 * RevenueCat Webhook (v2 HTTPS)
 * Verifies Authorization header with secret stored in Secret Manager.
 * Maps infinite_brain / creation_engine to accountTier on users/{app_user_id}.
 */
exports.revenuecatWebhook = onRequest(
  { secrets: [revenuecatWebhookSecret] },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).send("Method Not Allowed");
    }

    const authHeader = req.headers.authorization;
    const expectedSecret = revenuecatWebhookSecret.value();

    if (
      !authHeader ||
      (authHeader !== expectedSecret && authHeader !== `Bearer ${expectedSecret}`)
    ) {
      console.warn("RevenueCat webhook: Unauthorized attempt.");
      return res.status(401).send("Unauthorized");
    }

    const body = req.body || {};
    const event = body.event;

    if (!event) {
      return res.status(400).send("Invalid webhook payload: missing event.");
    }

    const appUserId = event.app_user_id;
    if (!appUserId) {
      return res.status(400).send("Missing app_user_id in event.");
    }

    // Determine target tier from event entitlements
    const entitlementIds = event.entitlement_ids || [];
    const entitlementId = event.entitlement_id;
    const allEntitlements = [...entitlementIds];
    if (entitlementId && !allEntitlements.includes(entitlementId)) {
      allEntitlements.push(entitlementId);
    }

    const eventType = event.type;
    let newTier = "Free";

    if (eventType === "EXPIRATION") {
      newTier = "Free";
    } else if (allEntitlements.includes("infinite_brain")) {
      newTier = "Infinite Brain";
    } else if (allEntitlements.includes("creation_engine")) {
      newTier = "Creation Engine";
    }

    try {
      await db.collection("users").doc(appUserId).set(
        {
          accountTier: newTier,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      console.log(`Updated user ${appUserId} accountTier to ${newTier} via webhook.`);
      return res.status(200).json({ success: true, tier: newTier });
    } catch (err) {
      console.error(`Failed to update user ${appUserId} tier:`, err);
      return res.status(500).send("Internal Server Error");
    }
  }
);

/**
 * syncEntitlements (Callable v2, App Check enforced)
 * Reads RevenueCat REST API for calling uid and updates accountTier.
 */
exports.syncEntitlements = onCall(
  { enforceAppCheck: true, secrets: [revenuecatSecretKey] },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;
    const rcSecret = revenuecatSecretKey.value();

    try {
      const response = await fetch(
        `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`,
        {
          headers: {
            Authorization: `Bearer ${rcSecret}`,
            "Content-Type": "application/json",
          },
        }
      );

      if (!response.ok) {
        console.error(`RevenueCat API returned status ${response.status}`);
        throw new HttpsError("internal", "Failed to retrieve subscription status.");
      }

      const data = await response.json();
      const entitlements = data.subscriber?.entitlements || {};

      const now = new Date();
      function isEntitlementActive(ent) {
        if (!ent) return false;
        if (!ent.expires_date) return true; // Lifetime
        return new Date(ent.expires_date) > now;
      }

      let newTier = "Free";
      if (isEntitlementActive(entitlements["infinite_brain"])) {
        newTier = "Infinite Brain";
      } else if (isEntitlementActive(entitlements["creation_engine"])) {
        newTier = "Creation Engine";
      }

      await db.collection("users").doc(uid).set(
        {
          accountTier: newTier,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      return { accountTier: newTier };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("Error in syncEntitlements:", err);
      throw new HttpsError("internal", "Could not sync subscription entitlements.");
    }
  }
);

// ============================================================================
// TASK 3: SERVER-SIDE GEMINI & RAG
// ============================================================================

/**
 * analyzeAsset (Callable v2, App Check enforced)
 * Runs AI vision / multimodal / document analysis, generates smart title,
 * structured summary, and category, and stores them in knowledge_base doc.
 */
exports.analyzeAsset = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey] },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;
    const { docId, fileUrl, fileType } = request.data || {};

    if (!docId || !fileUrl) {
      throw new HttpsError("invalid-argument", "Missing docId or fileUrl.");
    }

    // Server-side quota enforcement
    await enforceQuotaTransaction(uid, "upload");

    const genAI = getGenAI();
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });

    let mimeType = "image/jpeg";
    let systemPrompt = `You are an expert data extraction engine for a personal Second Brain app.
Analyze the provided asset. If the input is a standard document or scene, provide a concise smartTitle and a detailed summary as instructed.

CRITICAL CONVERSATION OVERRIDE: If the input image is identified as a chat message thread, direct message log, or a tall rolling screenshot from applications like WhatsApp, iMessage, Telegram, Slack, or Discord:
1. Bypass standard paragraph summaries.
2. Transcribe the entire conversation thread chronologically from top to bottom.
3. Format the 'summary' output field strictly as a clean, highly readable dialogue script using markdown bolding for names:
   **[Sender/Left Side]**: Message text here
   **[Receiver/Right Side]**: Response text here
4. Generate a 'smartTitle' that summarizes the core relationship or outcome of that specific discussion thread.
`;

    if (fileType === "pdf") {
      mimeType = "application/pdf";
      systemPrompt += "Extract all textual data via deep OCR. Identify core concepts, critical names, data points, entities, and provide an exhaustive analytical summary.";
    } else if (["mp3", "m4a", "wav"].includes(fileType)) {
      mimeType = "audio/mp3";
      systemPrompt += "Listen to this audio track carefully. Transcribe the spoken text entirely, analyze the conversational tone, summarize the core topics discussed, and output key takeaways.";
    } else if (["mp4", "mov"].includes(fileType)) {
      mimeType = "video/mp4";
      systemPrompt += "Watch this video clip sequentially. Detect key scenes, summarize visual actions, transcribe background audio tracks, and create a timeline summary of what occurs.";
    } else {
      mimeType = "image/jpeg";
      systemPrompt += "Perform an image analysis. Read any overlay text via OCR, detect visible objects, actions, human expressions, emotional mood, and summarize the overall context.";
    }

    systemPrompt += `\nFormat your response strictly as JSON: { "title": "...", "summary": "...", "category": "..." }. For the category field, strictly choose the single best fit from these exact 6 options: [health, people, photos, work, documents, events].`;

    try {
      const fileRes = await fetch(fileUrl);
      const arrayBuffer = await fileRes.arrayBuffer();
      const base64Data = Buffer.from(arrayBuffer).toString("base64");

      const result = await model.generateContent([
        {
          inlineData: {
            mimeType: mimeType,
            data: base64Data,
          },
        },
        systemPrompt,
      ]);

      const rawText = result.response.text() || "{}";

      let titleToSave = "Note";
      let summaryToSave = rawText.trim();
      let categoryToSave = "documents";

      try {
        let jsonText = rawText;
        if (jsonText.includes("```json")) {
          jsonText = jsonText.split("```json")[1].split("```")[0].trim();
        } else if (jsonText.includes("{")) {
          jsonText = jsonText.substring(
            jsonText.indexOf("{"),
            jsonText.lastIndexOf("}") + 1
          );
        }
        const parsed = JSON.parse(jsonText);
        if (parsed.title) titleToSave = parsed.title;
        if (parsed.summary) summaryToSave = parsed.summary;
        if (parsed.category) categoryToSave = parsed.category.toLowerCase();
      } catch (e) {
        console.warn("JSON parse fallback on analyzeAsset:", e);
      }

      // Update Firestore document directly from the server
      await db
        .collection("users")
        .doc(uid)
        .collection("knowledge_base")
        .doc(docId)
        .set(
          {
            smartTitle: titleToSave,
            aiSummary: summaryToSave,
            category: categoryToSave,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

      return {
        title: titleToSave,
        summary: summaryToSave,
        category: categoryToSave,
      };
    } catch (err) {
      console.error("Error in analyzeAsset:", err);
      throw new HttpsError("internal", "Failed to analyze asset.");
    }
  }
);

/**
 * extractEvents (Callable v2, App Check enforced)
 * Solves Event Reminder Timezone Bug (Task 4):
 * Receives device IANA timezone and current local date.
 * Resolves relative dates against currentDate.
 * Formats eventDateTime with explicit ISO8601 timezone offset.
 * For date-only events, defaults to 09:00:00 with the timezone offset.
 */
exports.extractEvents = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey] },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;
    const { docId, summaryText, timezone, currentDate } = request.data || {};

    if (!summaryText) {
      return { events: [] };
    }

    const userTz = timezone || "UTC";
    const userDate = currentDate || new Date().toISOString().split("T")[0];

    const genAI = getGenAI();
    const model = genAI.getGenerativeModel({
      model: "gemini-2.5-flash",
      generationConfig: { responseMimeType: "application/json" },
    });

    const prompt = `Analyze the following text for any identifiable timeline variables or scheduled events (e.g. meeting dates, locations, calendar slots, appointment confirmations).
User Timezone: ${userTz}
Current Reference Date: ${userDate}

CRITICAL TIMEZONE & DATE RULES:
1. Resolve all relative dates (such as "tomorrow", "this Friday", "next Monday") relative to the Current Reference Date: ${userDate}.
2. For "eventDateTime", format it as a valid ISO8601 string WITH the explicit local timezone offset for ${userTz} (for example: "2026-10-12T14:30:00-06:00" or "2026-10-12T14:30:00+01:00"). Never output a trailing "Z".
3. If an event has a specific date but NO specific time is mentioned, set the time to exactly 09:00:00 on that day with the timezone offset (for example: "2026-10-12T09:00:00-06:00").
4. Return a JSON array of objects, where each object has these strictly named string keys: "eventTitle", "eventDateTime", "eventLocation".
5. If no events are found, return an empty array [].

Text to analyze:
${summaryText}`;

    try {
      const response = await model.generateContent(prompt);
      const text = response.response.text();
      let events = [];

      if (text) {
        try {
          events = JSON.parse(text);
        } catch (parseErr) {
          console.warn("Failed to parse event extraction JSON:", parseErr);
        }
      }

      if (Array.isArray(events) && events.length > 0) {
        const batch = db.batch();
        const eventsRef = db
          .collection("users")
          .doc(uid)
          .collection("upcoming_events");

        for (const ev of events) {
          const docRef = eventsRef.doc();
          batch.set(docRef, {
            sourceDocId: docId || "",
            eventTitle: ev.eventTitle || "Unknown Event",
            eventDateTime: ev.eventDateTime || "TBD",
            eventLocation: ev.eventLocation || "TBD",
            timezone: userTz,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        await batch.commit();
      }

      return { events };
    } catch (err) {
      console.error("Error in extractEvents:", err);
      throw new HttpsError("internal", "Failed to extract events.");
    }
  }
);

/**
 * chatWithRag (Callable v2, App Check enforced)
 * Performs server-side RAG retrieval (top 15 recent items capped at ~6000 chars),
 * conversation history lookup, quota enforcement, and Gemini response streaming/generation.
 */
exports.chatWithRag = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey] },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;
    const { prompt, chatId, mediaUrl, mediaType, fileName, messageType } =
      request.data || {};

    if (!prompt && !mediaUrl) {
      throw new HttpsError("invalid-argument", "Missing prompt or media.");
    }

    const activeChatId = chatId || db.collection("users").doc(uid).collection("chats").doc().id;

    // Enforce chat quota
    await enforceQuotaTransaction(uid, "chat");

    // 1. Fetch server-side RAG context (capped to top 15 recents, max 6000 chars total)
    const kbSnapshot = await db
      .collection("users")
      .doc(uid)
      .collection("knowledge_base")
      .orderBy("uploadedAt", "desc")
      .limit(15)
      .get();

    let contextChars = 0;
    const MAX_CONTEXT_CHARS = 6000;
    const contextLines = [];

    for (const doc of kbSnapshot.docs) {
      const data = doc.data();
      const name = data.fileName || data.title || "Document";
      const summary = data.aiSummary || "";
      if (summary) {
        const line = `Document Source [Name: ${name}]: ${summary}`;
        if (contextChars + line.length > MAX_CONTEXT_CHARS) break;
        contextLines.push(line);
        contextChars += line.length;
      }
    }
    const retrievedContext = contextLines.join("\n\n");

    // 2. Fetch recent conversation history (last 6 messages)
    const historySnapshot = await db
      .collection("users")
      .doc(uid)
      .collection("chats")
      .doc(activeChatId)
      .collection("messages")
      .orderBy("timestamp", "desc")
      .limit(6)
      .get();

    // 3. Store user message in Firestore
    const userMsgData = {
      senderId: uid,
      role: "user",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      type: messageType || (mediaUrl ? "mixed" : "text"),
      content: prompt || mediaUrl,
    };
    if (mediaUrl) {
      userMsgData.mediaUrl = mediaUrl;
      userMsgData.fileName = fileName;
    }

    await db
      .collection("users")
      .doc(uid)
      .collection("chats")
      .doc(activeChatId)
      .collection("messages")
      .add(userMsgData);

    // 4. Build prompt contents for Gemini
    const contents = [];
    const historyDocs = historySnapshot.docs.reverse();

    for (const doc of historyDocs) {
      const mData = doc.data();
      const role = mData.role === "ai" || mData.role === "assistant" ? "model" : "user";
      const content = mData.content || "";
      if (content) {
        contents.push({ role, parts: [{ text: content }] });
      }
    }

    // Append current user turn with RAG system context
    const currentPromptText = `You are the Axiom AI Second Brain. You possess access to the user's private knowledge vault records.
Here are the current facts from their ingested vault items:
${retrievedContext || "No previous documents currently indexed."}

Using the file facts outlined above whenever relevant, answer the user's prompt accurately:
${prompt || "[User attached media]"}`;

    const currentParts = [{ text: currentPromptText }];

    if (mediaUrl && mediaType) {
      try {
        const res = await fetch(mediaUrl);
        const buf = await res.arrayBuffer();
        currentParts.push({
          inlineData: {
            mimeType: mediaType,
            data: Buffer.from(buf).toString("base64"),
          },
        });
      } catch (err) {
        console.warn("Could not inline attached media in chat:", err);
      }
    }

    contents.push({ role: "user", parts: currentParts });

    // 5. Call Gemini
    const genAI = getGenAI();
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });

    try {
      const response = await model.generateContent({ contents });
      const aiResponse = response.response.text();

      // Store AI message in Firestore
      await db
        .collection("users")
        .doc(uid)
        .collection("chats")
        .doc(activeChatId)
        .collection("messages")
        .add({
          senderId: "system",
          role: "ai",
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          type: "text",
          content: aiResponse,
        });

      return {
        response: aiResponse,
        chatId: activeChatId,
      };
    } catch (err) {
      console.error("Gemini chat error:", err);
      throw new HttpsError("internal", "Failed to generate chat response.");
    }
  }
);

/**
 * synthesizeCreation (Callable v2, App Check enforced)
 * Creation Engine narrative synthesis based on user knowledge vault.
 */
exports.synthesizeCreation = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey] },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;
    const { prompt } = request.data || {};

    if (!prompt) {
      throw new HttpsError("invalid-argument", "Missing prompt.");
    }

    // Quota check
    await enforceQuotaTransaction(uid, "chat");

    const kbSnapshot = await db
      .collection("users")
      .doc(uid)
      .collection("knowledge_base")
      .orderBy("uploadedAt", "desc")
      .limit(20)
      .get();

    let allSummaries = kbSnapshot.docs
      .map((d) => {
        const data = d.data();
        return `Asset: ${data.fileName || "File"} | Summary: ${data.aiSummary || ""}`;
      })
      .join("\n\n");

    if (allSummaries.length > 6000) {
      allSummaries = allSummaries.substring(0, 6000);
    }

    const systemInstruction = `You are the Axiom Creation Engine. Review this vault of user-ingested knowledge memories: [VAULT: ${allSummaries || "Empty vault"}]. Based entirely on these personal records, fulfill the user's creative generation request: ${prompt}. Build an emotionally engaging, structurally sound narrative story arc or compilation response. Deliver the result in beautiful markdown styling.`;

    const genAI = getGenAI();
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });

    try {
      const result = await model.generateContent(systemInstruction);
      const text = result.response.text();
      return { content: text };
    } catch (err) {
      console.error("synthesizeCreation error:", err);
      throw new HttpsError("internal", "Failed to synthesize narrative.");
    }
  }
);

/**
 * generateStoryboard (Callable v2, App Check enforced)
 * Synthesizes a chronological video narrative story arc script layout from cluster items.
 */
exports.generateStoryboard = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey] },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const { summaries, dateKey } = request.data || {};
    if (!Array.isArray(summaries) || summaries.length === 0) {
      throw new HttpsError("invalid-argument", "Missing summaries array.");
    }

    const prompt = `Act as a Master Short-Form Director. Analyze these media segment summaries representing a cluster of memories (${dateKey || ""}).
Synthesize a definitive chronological video narrative story arc script layout.
Generate dynamic subtitle text overlays for every slide/scene transition and suggest an overarching theme vibe or musical tempo score template.
Package everything into a striking markdown screen array using ## headers, bullet points, and blockquotes for visual flair.

Summaries:
${summaries.join("\n\n---\n\n")}`;

    const genAI = getGenAI();
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });

    try {
      const result = await model.generateContent(prompt);
      const text = result.response.text();
      return { storyboard: text };
    } catch (err) {
      console.error("generateStoryboard error:", err);
      throw new HttpsError("internal", "Failed to generate storyboard narrative.");
    }
  }
);

/**
 * generateTitle (Callable v2, App Check enforced)
 * Generates descriptive 3-to-4 word summary title for pasted text or note.
 */
exports.generateTitle = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey] },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const { text } = request.data || {};
    if (!text) {
      return { title: "Untitled Note" };
    }

    const snippet = text.substring(0, Math.min(text.length, 500));
    const prompt = `Review this pasted text snippet. Generate a highly descriptive, professional 3-to-4 word summary title. Return exclusively the raw title text string without any introductory phrases, wrap text, or punctuation marks. Text: ${snippet}`;

    const genAI = getGenAI();
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });

    try {
      const response = await model.generateContent(prompt);
      let title = response.response.text()?.trim() || "Untitled Note";
      title = title.replace(/["\n]/g, " ").trim();
      return { title };
    } catch (err) {
      console.error("generateTitle error:", err);
      return { title: "Untitled Note" };
    }
  }
);

/**
 * enhanceText (Callable v2, App Check enforced)
 * Analyzes raw pasted text, extracts key themes, and saves structured summary.
 */
exports.enhanceText = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey] },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;
    const { docId, rawText } = request.data || {};

    if (!docId || !rawText) {
      throw new HttpsError("invalid-argument", "Missing docId or rawText.");
    }

    const prompt = `Analyze this raw text. Extract key themes and rewrite it into a highly optimized, structured summary. Return ONLY the summary.\n\nText: ${rawText}`;

    const genAI = getGenAI();
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });

    try {
      const response = await model.generateContent(prompt);
      const enhancedSummary = response.response.text()?.trim() || rawText;

      await db
        .collection("users")
        .doc(uid)
        .collection("knowledge_base")
        .doc(docId)
        .set({ aiSummary: enhancedSummary }, { merge: true });

      return { summary: enhancedSummary };
    } catch (err) {
      console.error("enhanceText error:", err);
      throw new HttpsError("internal", "Failed to enhance text summary.");
    }
  }
);

/**
 * getEmbedding (Callable v2, App Check enforced)
 * Computes vector embeddings via text-embedding-004.
 */
exports.getEmbedding = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey] },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const { query } = request.data || {};
    if (!query) {
      return { embedding: [] };
    }

    const genAI = getGenAI();
    const model = genAI.getGenerativeModel({ model: "text-embedding-004" });

    try {
      const result = await model.embedContent(query);
      return { embedding: result.embedding.values || [] };
    } catch (err) {
      console.error("getEmbedding error:", err);
      throw new HttpsError("internal", "Failed to generate embedding.");
    }
  }
);

/**
 * updateChatTitle (Callable v2, App Check enforced)
 * Inspects initial messages and auto-titles the conversation session.
 */
exports.updateChatTitle = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey] },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;
    const { chatId } = request.data || {};
    if (!chatId) {
      throw new HttpsError("invalid-argument", "Missing chatId.");
    }

    const messagesSnapshot = await db
      .collection("users")
      .doc(uid)
      .collection("chats")
      .doc(chatId)
      .collection("messages")
      .orderBy("timestamp", "asc")
      .limit(2)
      .get();

    const openingContent = messagesSnapshot.docs
      .map((d) => {
        const data = d.data();
        const role = data.role === "ai" ? "AI" : "User";
        return `${role}: ${data.content}`;
      })
      .join("\n");

    const prompt = `Review these opening messages from a chat session. Generate a highly descriptive, professional 3-to-4 word summary title for this conversation. Return exclusively the raw title text string without any introductory phrases, wrap text, or punctuation marks. Conversation logs: ${openingContent}`;

    const genAI = getGenAI();
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });

    try {
      const response = await model.generateContent(prompt);
      let title = response.response.text()?.trim() || "New Conversation";
      title = title.replace(/[*"]/g, "").trim();

      await db
        .collection("users")
        .doc(uid)
        .collection("chats")
        .doc(chatId)
        .set({ title }, { merge: true });

      return { title };
    } catch (err) {
      console.error("updateChatTitle error:", err);
      return { title: "New Conversation" };
    }
  }
);

/**
 * Fixed analyzeMedia (Callable v2, App Check enforced)
 * 1. Checks `users/${uid}/` path instead of broken `uploads/${uid}/`
 * 2. Stops deleting the user's file after analysis if vault still references it
 * 3. Uses defineSecret for GEMINI_API_KEY
 */
exports.analyzeMedia = onCall(
  { enforceAppCheck: true, secrets: [geminiApiKey] },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;
    const { prompt, mediaPath, mediaType } = request.data || {};

    if (!prompt) {
      throw new HttpsError("invalid-argument", "Missing 'prompt' in request.");
    }

    await enforceQuotaTransaction(uid, "upload");

    const genAI = getGenAI();
    const model = genAI.getGenerativeModel({
      model: "gemini-2.5-flash",
      systemInstruction: "You are the Neural Canvas Digital Memory Assistant...",
    });

    const contentParts = [prompt];

    if (mediaPath && mediaType) {
      // Fix: Verify path starts with users/{uid}/
      if (!mediaPath.startsWith(`users/${uid}/`)) {
        throw new HttpsError(
          "permission-denied",
          "You can only process your own files."
        );
      }

      const bucket = admin.storage().bucket();
      const file = bucket.file(mediaPath);
      const [buffer] = await file.download();

      contentParts.push({
        inlineData: {
          data: buffer.toString("base64"),
          mimeType: mediaType,
        },
      });

      // Stop deleting user's file! The user's vault still references this file.
    }

    try {
      const aiResponse = await model.generateContent(contentParts);
      const outputText = aiResponse.response.text();
      return { response: outputText };
    } catch (error) {
      console.error("Gemini Error in analyzeMedia:", error);
      throw new HttpsError("internal", "Failed to communicate with Neural Core.");
    }
  }
);

// ============================================================================
// TASK 5: SERVER-SIDE COMPLETE ACCOUNT DELETION
// ============================================================================

/**
 * deleteAccount (Callable v2, App Check enforced)
 * Recursively purges all user data:
 * - knowledge_base subcollection
 * - chats subcollection and nested messages
 * - upcoming_events subcollection
 * - usage subcollection
 * - user profile document /users/{uid}
 * - all Firebase Storage files under users/{uid}/
 * - Firebase Authentication user account
 */
exports.deleteAccount = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }

  const uid = request.auth.uid;
  console.log(`Starting complete account purge for user: ${uid}`);

  try {
    // 1. Delete all Storage files under users/{uid}/
    try {
      const bucket = admin.storage().bucket();
      await bucket.deleteFiles({ prefix: `users/${uid}/` });
      console.log(`Storage files for users/${uid}/ successfully purged.`);
    } catch (storageErr) {
      console.warn("Storage deletion error (continuing purge):", storageErr);
    }

    // 2. Recursively delete Firestore collections
    const userDocRef = db.collection("users").doc(uid);

    // Delete nested chat messages then chats
    const chatsSnap = await userDocRef.collection("chats").get();
    for (const chatDoc of chatsSnap.docs) {
      const messagesSnap = await chatDoc.ref.collection("messages").get();
      const msgBatch = db.batch();
      messagesSnap.docs.forEach((m) => msgBatch.delete(m.ref));
      await msgBatch.commit();
      await chatDoc.ref.delete();
    }

    // Subcollections to purge
    const subcollections = ["knowledge_base", "upcoming_events", "usage"];
    for (const subName of subcollections) {
      const subSnap = await userDocRef.collection(subName).get();
      if (!subSnap.empty) {
        const batch = db.batch();
        subSnap.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
      }
    }

    // Delete root user document
    await userDocRef.delete();
    console.log(`Firestore documents for user ${uid} successfully purged.`);

    // 3. Delete Firebase Auth user
    await admin.auth().deleteUser(uid);
    console.log(`Auth record for user ${uid} successfully deleted.`);

    return { success: true };
  } catch (err) {
    console.error(`Failed to completely delete account for user ${uid}:`, err);
    throw new HttpsError("internal", "Account deletion encountered an issue.");
  }
});
