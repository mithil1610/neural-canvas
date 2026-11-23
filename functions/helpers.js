// Pure helpers used by index.js. No Firebase or network access here, so they can be unit tested.

const ALLOWED_CATEGORIES = ["health", "people", "photos", "work", "documents", "events"];

const EXT_MIME = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  gif: "image/gif",
  webp: "image/webp",
  heic: "image/heic",
  heif: "image/heif",
  pdf: "application/pdf",
  txt: "text/plain",
  md: "text/plain",
  rtf: "text/rtf",
  doc: "application/msword",
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  m4a: "audio/mp4",
  mp3: "audio/mpeg",
  wav: "audio/wav",
  aac: "audio/aac",
  mp4: "video/mp4",
  mov: "video/quicktime",
};

/**
 * Resolves the Storage object path for a user file and verifies it belongs to that user.
 * Accepts either an explicit storage path or a Firebase Storage download URL
 * (https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<encoded path>?...).
 * Throws an Error with .code = "invalid-argument" | "permission-denied".
 */
function resolveUserStoragePath(uid, { storagePath, fileUrl } = {}) {
  let path = typeof storagePath === "string" && storagePath ? storagePath : null;
  if (!path && typeof fileUrl === "string" && fileUrl) {
    const m = /^https:\/\/firebasestorage\.googleapis\.com\/v0\/b\/[^/]+\/o\/([^?#]+)/.exec(fileUrl);
    if (!m) throw codedError("invalid-argument", "Unsupported file URL.");
    try {
      path = decodeURIComponent(m[1]);
    } catch (_) {
      throw codedError("invalid-argument", "Malformed file URL.");
    }
  }
  if (!path) throw codedError("invalid-argument", "Missing file reference.");
  if (!uid || !path.startsWith(`users/${uid}/`) || path.includes("..") || path.includes("\\")) {
    throw codedError("permission-denied", "You can only process your own files.");
  }
  return path;
}

function codedError(code, message) {
  const e = new Error(message);
  e.code = code;
  return e;
}

function extOf(pathOrName) {
  const base = String(pathOrName || "").split("?")[0].split("/").pop() || "";
  const i = base.lastIndexOf(".");
  return i >= 0 ? base.slice(i + 1).toLowerCase() : "";
}

/** Picks the MIME type: the stored contentType when it is specific, else the file extension. */
function resolveMime(contentType, pathOrName, fileTypeHint) {
  const ct = String(contentType || "").toLowerCase().split(";")[0].trim();
  if (ct && ct !== "application/octet-stream") return ct === "audio/x-m4a" ? "audio/mp4" : ct;
  return EXT_MIME[extOf(pathOrName)] || EXT_MIME[String(fileTypeHint || "").toLowerCase()] || "application/octet-stream";
}

function mediaKind(mime) {
  if (mime.startsWith("image/")) return "image";
  if (mime.startsWith("audio/")) return "audio";
  if (mime.startsWith("video/")) return "video";
  if (mime === "application/pdf") return "pdf";
  if (mime === EXT_MIME.docx) return "docx";
  if (mime === EXT_MIME.doc) return "doc";
  if (mime.startsWith("text/")) return "text";
  return "unknown";
}

function normalizeCategory(c) {
  const v = String(c || "").toLowerCase().trim();
  return ALLOWED_CATEGORIES.includes(v) ? v : "documents";
}

/** Extracts the first JSON object or array from a model response. */
function parseJsonLoose(text) {
  if (!text) return null;
  let t = String(text).trim();
  const fence = /```(?:json)?\s*([\s\S]*?)```/i.exec(t);
  if (fence) t = fence[1].trim();
  try {
    return JSON.parse(t);
  } catch (_) {
    const starts = [t.indexOf("{"), t.indexOf("[")].filter((i) => i >= 0);
    if (!starts.length) return null;
    const s = Math.min(...starts);
    const e = Math.max(t.lastIndexOf("}"), t.lastIndexOf("]"));
    if (e <= s) return null;
    try {
      return JSON.parse(t.slice(s, e + 1));
    } catch (_) {
      return null;
    }
  }
}

/**
 * Normalizes an event time from the model to a local wall-clock string with no offset:
 * "YYYY-MM-DD" (date only) or "YYYY-MM-DDTHH:MM:SS". Returns "TBD" when unusable.
 * Any trailing "Z" or "+hh:mm" is dropped, because the prompt asks for local time.
 */
function normalizeEventDateTime(raw) {
  const s = String(raw || "").trim();
  const m = /^(\d{4}-\d{2}-\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?$/.exec(s);
  if (!m) return "TBD";
  const [, date, hh, mm, ss] = m;
  if (hh === undefined) return date;
  return `${date}T${hh}:${mm}:${ss || "00"}`;
}

function cosine(a, b) {
  if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length || a.length === 0) return 0;
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return na && nb ? dot / (Math.sqrt(na) * Math.sqrt(nb)) : 0;
}

const STOP = new Set(("the a an and or of to in on at for is are was were be my me i you your what when where " +
  "who how which do does did can could should would with from about this that it its it's whats what's").split(" "));

function keywords(text) {
  return Array.from(new Set(String(text || "").toLowerCase().match(/[a-z0-9][a-z0-9'_-]{2,}/g) || []))
    .filter((w) => !STOP.has(w));
}

/**
 * Ranks vault items for a question. items: [{id, title, summary, embedding?, recency (0 = newest)}].
 * Score = cosine similarity (if both embeddings exist) + keyword boosts + a small recency bonus.
 */
function rankItems(items, question, queryEmbedding, topK = 12) {
  const kws = keywords(question);
  const scored = items.map((it) => {
    const title = String(it.title || "").toLowerCase();
    const summary = String(it.summary || "").toLowerCase();
    let score = queryEmbedding && it.embedding ? cosine(queryEmbedding, it.embedding) : 0;
    let titleHits = 0, bodyHits = 0;
    for (const k of kws) {
      if (title.includes(k)) titleHits++;
      else if (summary.includes(k)) bodyHits++;
    }
    score += Math.min(0.3, 0.15 * titleHits) + Math.min(0.2, 0.05 * bodyHits);
    score += Math.max(0, 0.05 - 0.002 * (it.recency || 0));
    return { ...it, score };
  });
  scored.sort((x, y) => y.score - x.score);
  return scored.slice(0, topK);
}

/** Builds the vault context block, capped in total and per item. */
function buildContext(items, maxChars = 8000, perItem = 900) {
  const lines = [];
  let used = 0;
  for (const it of items) {
    const summary = String(it.summary || "").slice(0, perItem);
    if (!summary) continue;
    const line = `Vault item [${it.title || "Untitled"}${it.date ? `, saved ${it.date}` : ""}]: ${summary}`;
    if (used + line.length > maxChars) break;
    lines.push(line);
    used += line.length;
  }
  return lines.join("\n\n");
}

/** Maps RevenueCat subscriber entitlements to an Axiom tier name. */
function tierFromEntitlements(entitlements, now = new Date()) {
  const active = (e) => !!e && (!e.expires_date || new Date(e.expires_date) > now);
  if (active(entitlements && entitlements.infinite_brain)) return "Infinite Brain";
  if (active(entitlements && entitlements.creation_engine)) return "Creation Engine";
  return "Free";
}

function isAnonymousRcId(id) {
  return typeof id === "string" && id.startsWith("$RCAnonymousID");
}

function utcDay(d = new Date()) {
  return d.toISOString().slice(0, 10);
}

module.exports = {
  ALLOWED_CATEGORIES,
  resolveUserStoragePath,
  resolveMime,
  mediaKind,
  extOf,
  normalizeCategory,
  parseJsonLoose,
  normalizeEventDateTime,
  cosine,
  keywords,
  rankItems,
  buildContext,
  tierFromEntitlements,
  isAnonymousRcId,
  utcDay,
};
