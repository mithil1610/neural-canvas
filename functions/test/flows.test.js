// End-to-end tests of the callable handlers with in-memory fakes for Firestore,
// Storage, Auth, Gemini and RevenueCat. No network or emulator needed.
const test = require("node:test");
const assert = require("node:assert/strict");
const Module = require("module");

process.env.GEMINI_API_KEY = "test-gemini";
process.env.REVENUECAT_SECRET_KEY = "sk_test";
process.env.REVENUECAT_WEBHOOK_SECRET = "hook-secret";
process.env.GCLOUD_PROJECT = "demo-axiom";

// ---------------- Fake Firestore ----------------
const store = new Map();
const TS = Symbol("ts");
class FakeTimestamp {
  constructor(d) { this.d = d; }
  toDate() { return this.d; }
}
const FieldValue = {
  serverTimestamp: () => ({ [TS]: true }),
  increment: (n) => ({ __inc: n }),
};
function applyFields(old, data) {
  const out = { ...(old || {}) };
  for (const [k, v] of Object.entries(data)) {
    if (v && v[TS]) out[k] = new FakeTimestamp(new Date());
    else if (v && typeof v === "object" && "__inc" in v) out[k] = (out[k] || 0) + v.__inc;
    else out[k] = v;
  }
  return out;
}
let autoId = 0;
function snap(ref) {
  const d = store.get(ref.path);
  return { id: ref.id, ref, exists: d !== undefined, data: () => (d ? { ...d } : undefined) };
}
class DocRef {
  constructor(path) { this.path = path; this.id = path.split("/").pop(); }
  collection(n) { return new Query(`${this.path}/${n}`); }
  async get() { return snap(this); }
  async set(data, opts) {
    const old = opts && opts.merge ? store.get(this.path) : undefined;
    store.set(this.path, applyFields(old, data));
  }
  async delete() { store.delete(this.path); }
}
class Query {
  constructor(path, order = null, lim = null) { this.path = path; this.order = order; this.lim = lim; }
  doc(id) { return new DocRef(`${this.path}/${id || "auto" + ++autoId}`); }
  async add(data) { const r = this.doc(); await r.set(data); return r; }
  orderBy(field, dir = "asc") { return new Query(this.path, { field, dir }, this.lim); }
  limit(n) { return new Query(this.path, this.order, n); }
  select() { return this; }
  async get() {
    const depth = this.path.split("/").length + 1;
    let docs = [...store.keys()]
      .filter((k) => k.startsWith(this.path + "/") && k.split("/").length === depth)
      .map((k) => snap(new DocRef(k)));
    if (this.order) {
      const { field, dir } = this.order;
      const val = (s) => { const v = s.data()[field]; return v instanceof FakeTimestamp ? v.d.getTime() : v; };
      docs = docs.filter((s) => s.data()[field] !== undefined);
      docs.sort((a, b) => (val(a) < val(b) ? -1 : val(a) > val(b) ? 1 : 0) * (dir === "desc" ? -1 : 1));
    }
    if (this.lim) docs = docs.slice(0, this.lim);
    return { docs, empty: docs.length === 0 };
  }
}
const db = {
  collection: (n) => new Query(n),
  async runTransaction(fn) {
    const ops = [];
    const tx = { get: (r) => r.get(), set: (r, d, o) => ops.push([r, d, o]) };
    const result = await fn(tx);
    for (const [r, d, o] of ops) await r.set(d, o);
    return result;
  },
  batch() {
    const ops = [];
    return { set: (r, d) => ops.push(() => r.set(d)), delete: (r) => ops.push(() => r.delete()), commit: async () => { for (const op of ops) await op(); } };
  },
  async recursiveDelete(ref) { for (const k of [...store.keys()]) if (k === ref.path || k.startsWith(ref.path + "/")) store.delete(k); },
};

// ---------------- Fake Storage / Auth ----------------
const files = new Map(); // path -> {buffer, contentType}
const bucket = {
  file: (p) => ({
    getMetadata: async () => { if (!files.has(p)) throw new Error("404"); return [{ size: files.get(p).buffer.length, contentType: files.get(p).contentType }]; },
    download: async () => [files.get(p).buffer],
  }),
  deleteFiles: async ({ prefix }) => { for (const k of [...files.keys()]) if (k.startsWith(prefix)) files.delete(k); },
};
const users = new Set(["u1", "u2"]);
const deletedUsers = [];

// ---------------- Fake Gemini ----------------
const geminiCalls = [];
let responder = () => "{}";
function fakeEmbed(text) {
  const v = new Array(768).fill(0);
  for (const w of String(text).toLowerCase().match(/[a-z0-9]{3,}/g) || []) {
    let h = 0;
    for (const c of w) h = (h * 31 + c.charCodeAt(0)) % 768;
    v[h] += 1;
  }
  v[767] += 0.01;
  return v;
}
class GoogleGenAI {
  constructor() {
    this.models = {
      generateContent: async (p) => { geminiCalls.push(p); return { text: responder(p) }; },
      embedContent: async ({ contents }) => ({ embeddings: [{ values: fakeEmbed(contents) }] }),
    };
  }
}

// ---------------- Module stubs ----------------
const stubs = {
  "firebase-admin/app": { initializeApp: () => ({}) },
  "firebase-admin/firestore": { getFirestore: () => db, FieldValue },
  "firebase-admin/storage": { getStorage: () => ({ bucket: () => bucket }) },
  "firebase-admin/auth": {
    getAuth: () => ({
      getUser: async (id) => { if (!users.has(id)) throw new Error("no user"); return { uid: id }; },
      deleteUser: async (id) => { deletedUsers.push(id); users.delete(id); },
    }),
  },
  "@google/genai": { GoogleGenAI },
  mammoth: { extractRawText: async () => ({ value: "Docx body text" }) },
};
const origLoad = Module._load;
Module._load = function (req, ...rest) { return stubs[req] || origLoad.call(this, req, ...rest); };

let rcEntitlements = {};
global.fetch = async () => ({ ok: true, json: async () => ({ subscriber: { entitlements: rcEntitlements } }) });

const F = require("../index.js");
const call = (fn, uid, data) => fn.run({ auth: uid ? { uid } : undefined, data });
const today = new Date().toISOString().slice(0, 10);
const URL = (p) => `https://firebasestorage.googleapis.com/v0/b/demo.appspot.com/o/${encodeURIComponent(p)}?alt=media&token=x`;

test.beforeEach(() => { store.clear(); files.clear(); geminiCalls.length = 0; responder = () => "{}"; });

test("analyzeAsset analyzes the caller's file, saves summary + embedding, counts quota", async () => {
  await db.collection("users").doc("u1").set({ accountTier: "Free" });
  files.set("users/u1/knowledge_base/1_lease.pdf", { buffer: Buffer.from("%PDF"), contentType: "application/pdf" });
  responder = () => JSON.stringify({ title: "Apartment Lease", summary: "Lease ends January 31, 2027.", category: "Documents" });
  const r = await call(F.analyzeAsset, "u1", { docId: "k1", fileUrl: URL("users/u1/knowledge_base/1_lease.pdf"), fileType: "pdf" });
  assert.equal(r.title, "Apartment Lease");
  const kb = store.get("users/u1/knowledge_base/k1");
  assert.equal(kb.category, "documents");
  assert.equal(kb.embedding.length, 768);
  assert.equal(store.get("users/u1").dailyUploadCount, 1);
  assert.equal(geminiCalls[0].contents[0].parts[0].inlineData.mimeType, "application/pdf");
});

test("analyzeAsset sends .docx as extracted text, not as an image", async () => {
  files.set("users/u1/knowledge_base/2_notes.docx", { buffer: Buffer.from("PK"), contentType: "" });
  responder = () => JSON.stringify({ title: "Notes", summary: "s", category: "work" });
  await call(F.analyzeAsset, "u1", { docId: "k2", fileUrl: URL("users/u1/knowledge_base/2_notes.docx"), fileType: "docx" });
  assert.match(geminiCalls[0].contents[0].parts[0].text, /Docx body text/);
});

test("analyzeAsset refuses another user's file and arbitrary URLs", async () => {
  files.set("users/u2/knowledge_base/x.png", { buffer: Buffer.from("x"), contentType: "image/png" });
  await assert.rejects(call(F.analyzeAsset, "u1", { docId: "k3", fileUrl: URL("users/u2/knowledge_base/x.png") }), { code: "permission-denied" });
  await assert.rejects(call(F.analyzeAsset, "u1", { docId: "k3", fileUrl: "https://evil.example/x.png" }), { code: "invalid-argument" });
});

test("daily upload quota blocks the 11th free upload", async () => {
  await db.collection("users").doc("u1").set({ accountTier: "Free", dailyUploadCount: 10, lastUploadDate: today });
  files.set("users/u1/a.png", { buffer: Buffer.from("x"), contentType: "image/png" });
  await assert.rejects(call(F.analyzeAsset, "u1", { docId: "k4", storagePath: "users/u1/a.png" }), { code: "resource-exhausted" });
  // A new UTC day resets it.
  await db.collection("users").doc("u1").set({ lastUploadDate: "2000-01-01" }, { merge: true });
  responder = () => JSON.stringify({ title: "t", summary: "s", category: "photos" });
  await call(F.analyzeAsset, "u1", { docId: "k4", storagePath: "users/u1/a.png" });
  assert.equal(store.get("users/u1").dailyUploadCount, 1);
});

test("chatWithRag finds an old lease among 40 newer items and stores both messages", async () => {
  const kb = db.collection("users").doc("u1").collection("knowledge_base");
  const base = Date.now();
  await kb.doc("lease").set({ smartTitle: "Apartment Lease", aiSummary: "Lease at 2240 N Clark ends January 31, 2027. Renewal notice due December 2, 2026.", uploadedAt: new FakeTimestamp(new Date(base - 1e9)) });
  for (let i = 0; i < 40; i++) {
    await kb.doc("p" + i).set({ smartTitle: "Sunset photo " + i, aiSummary: "Orange sky over the lake with boats.", uploadedAt: new FakeTimestamp(new Date(base - i * 1000)) });
  }
  responder = () => "January 31, 2027.";
  const r = await call(F.chatWithRag, "u1", { prompt: "When does my lease end?", chatId: "c1" });
  assert.equal(r.response, "January 31, 2027.");
  const sent = geminiCalls[0].contents.at(-1).parts[0].text;
  assert.match(sent, /January 31, 2027/);
  const msgs = (await db.collection("users").doc("u1").collection("chats").doc("c1").collection("messages").get()).docs;
  assert.equal(msgs.length, 2);
  assert.equal(store.get("users/u1").dailyChatCount, 1);
  // Items saved before 1.3.0 get embeddings backfilled lazily.
  assert.ok([...store.keys()].some((k) => k.startsWith("users/u1/knowledge_base/") && store.get(k).embedding));
});

test("extractEvents returns local wall time and stores sortable strings", async () => {
  responder = () => JSON.stringify([
    { eventTitle: "Dentist", eventDateTime: "2026-12-15T10:30:00-06:00", eventLocation: "Lakeview" },
    { eventTitle: "Renewal notice", eventDateTime: "2026-12-02", eventLocation: "" },
    { eventTitle: "Someday", eventDateTime: "soon" },
  ]);
  const r = await call(F.extractEvents, "u1", { docId: "k1", summaryText: "x", timezone: "America/Chicago", currentDate: "2026-11-22" });
  assert.deepEqual(r.events.map((e) => e.eventDateTime), ["2026-12-15T10:30:00", "2026-12-02"]);
  const stored = (await db.collection("users").doc("u1").collection("upcoming_events").get()).docs.map((d) => d.data());
  assert.deepEqual(stored.map((e) => e.eventDateTime).sort(), ["2026-12-02T09:00:00", "2026-12-15T10:30:00"]);
  assert.match(geminiCalls[0].contents[0].parts[0].text, /America\/Chicago/);
});

test("paid features are gated on the server", async () => {
  await db.collection("users").doc("u1").set({ accountTier: "Free" });
  await assert.rejects(call(F.synthesizeCreation, "u1", { prompt: "write a story" }), { code: "permission-denied" });
  await assert.rejects(call(F.generateStoryboard, "u1", { summaries: ["a"] }), { code: "permission-denied" });
  await db.collection("users").doc("u1").set({ accountTier: "Creation Engine" }, { merge: true });
  responder = () => "# Story";
  assert.equal((await call(F.synthesizeCreation, "u1", { prompt: "write a story" })).content, "# Story");
  await assert.rejects(call(F.generateStoryboard, "u1", { summaries: ["a"] }), { code: "permission-denied" });
});

test("callables require sign-in", async () => {
  await assert.rejects(call(F.chatWithRag, null, { prompt: "hi" }), { code: "unauthenticated" });
});

function fakeRes() {
  const res = { statusCode: 200, body: null };
  res.status = (c) => { res.statusCode = c; return res; };
  res.send = (b) => { res.body = b; return res; };
  res.json = (b) => { res.body = b; return res; };
  return res;
}
const hookReq = (auth, event) => ({ method: "POST", body: { event }, headers: { authorization: auth }, get: (h) => (h.toLowerCase() === "authorization" ? auth : undefined) });

test("RevenueCat webhook: auth, TEST events, anonymous IDs and real refresh", async () => {
  let res = fakeRes();
  await F.revenuecatWebhook(hookReq("wrong", { type: "INITIAL_PURCHASE", app_user_id: "u1" }), res);
  assert.equal(res.statusCode, 401);

  res = fakeRes();
  await F.revenuecatWebhook(hookReq("hook-secret", { type: "TEST", app_user_id: "u1" }), res);
  assert.equal(res.statusCode, 200);
  assert.equal(store.size, 0);

  res = fakeRes();
  await F.revenuecatWebhook(hookReq("Bearer hook-secret", { type: "INITIAL_PURCHASE", app_user_id: "$RCAnonymousID:abc" }), res);
  assert.equal(res.body.updated, 0);
  assert.equal(store.size, 0);

  rcEntitlements = { infinite_brain: { expires_date: "2099-01-01T00:00:00Z" } };
  res = fakeRes();
  await F.revenuecatWebhook(hookReq("hook-secret", { type: "RENEWAL", app_user_id: "u1", aliases: ["$RCAnonymousID:abc", "u1"] }), res);
  assert.equal(res.statusCode, 200);
  assert.equal(store.get("users/u1").accountTier, "Infinite Brain");

  // Expiration of one plan while the other is active: tier comes from RevenueCat's current state.
  rcEntitlements = { infinite_brain: { expires_date: "2000-01-01T00:00:00Z" }, creation_engine: { expires_date: "2099-01-01T00:00:00Z" } };
  await F.revenuecatWebhook(hookReq("hook-secret", { type: "EXPIRATION", app_user_id: "u1" }), fakeRes());
  assert.equal(store.get("users/u1").accountTier, "Creation Engine");

  // Unknown (non-Firebase) IDs never create profile docs.
  await F.revenuecatWebhook(hookReq("hook-secret", { type: "RENEWAL", app_user_id: "not-a-user" }), fakeRes());
  assert.equal(store.has("users/not-a-user"), false);
});

test("deleteAccount purges Firestore (any depth), Storage and Auth", async () => {
  await db.collection("users").doc("u2").set({ fullName: "B" });
  await db.collection("users").doc("u2").collection("chats").doc("c").collection("messages").doc("m").set({ content: "x" });
  for (let i = 0; i < 600; i++) await db.collection("users").doc("u2").collection("knowledge_base").doc("k" + i).set({ a: i });
  files.set("users/u2/knowledge_base/a.png", { buffer: Buffer.from("x"), contentType: "image/png" });
  await db.collection("users").doc("u1").set({ fullName: "A" });
  await call(F.deleteAccount, "u2", {});
  assert.equal([...store.keys()].filter((k) => k.startsWith("users/u2")).length, 0);
  assert.equal(files.size, 0);
  assert.deepEqual(deletedUsers, ["u2"]);
  assert.ok(store.has("users/u1"));
});
