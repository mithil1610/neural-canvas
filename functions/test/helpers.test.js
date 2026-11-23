const test = require("node:test");
const assert = require("node:assert/strict");
const H = require("../helpers");

test("resolveUserStoragePath accepts the caller's download URL", () => {
  const url = "https://firebasestorage.googleapis.com/v0/b/demo.appspot.com/o/users%2Fabc123%2Fknowledge_base%2F1_a.pdf?alt=media&token=t";
  assert.equal(H.resolveUserStoragePath("abc123", { fileUrl: url }), "users/abc123/knowledge_base/1_a.pdf");
});

test("resolveUserStoragePath rejects another user's file and foreign URLs", () => {
  const url = "https://firebasestorage.googleapis.com/v0/b/demo.appspot.com/o/users%2Fother%2Fx.png?alt=media";
  assert.throws(() => H.resolveUserStoragePath("abc123", { fileUrl: url }), /own files/);
  assert.throws(() => H.resolveUserStoragePath("abc123", { fileUrl: "http://169.254.169.254/latest" }), /Unsupported/);
  assert.throws(() => H.resolveUserStoragePath("abc123", { storagePath: "users/abc123/../other/x" }), /own files/);
});

test("resolveMime prefers stored content type, falls back to extension", () => {
  assert.equal(H.resolveMime("image/heic", "users/u/a.heic"), "image/heic");
  assert.equal(H.resolveMime("application/octet-stream", "users/u/a.m4a"), "audio/mp4");
  assert.equal(H.resolveMime("", "users/u/a.docx"), "application/vnd.openxmlformats-officedocument.wordprocessingml.document");
  assert.equal(H.mediaKind(H.resolveMime("", "x.docx")), "docx");
});

test("normalizeEventDateTime strips offsets and keeps local wall time", () => {
  assert.equal(H.normalizeEventDateTime("2027-03-20T14:30:00-06:00"), "2027-03-20T14:30:00");
  assert.equal(H.normalizeEventDateTime("2026-12-15T10:30:00Z"), "2026-12-15T10:30:00");
  assert.equal(H.normalizeEventDateTime("2026-12-15 10:30"), "2026-12-15T10:30:00");
  assert.equal(H.normalizeEventDateTime("2026-12-02"), "2026-12-02");
  assert.equal(H.normalizeEventDateTime("next friday"), "TBD");
});

test("rankItems surfaces an old but relevant item over recent noise", () => {
  const items = [];
  for (let i = 0; i < 40; i++) items.push({ id: "n" + i, title: "Sunset photo " + i, summary: "Orange sky over the lake", recency: i });
  items.push({ id: "lease", title: "Apartment Lease", summary: "Lease ends January 31, 2027. Renewal notice due December 2, 2026.", recency: 40 });
  const top = H.rankItems(items, "When does my lease end?", null, 5);
  assert.equal(top[0].id, "lease");
});

test("tierFromEntitlements handles expiry and both plans", () => {
  const now = new Date("2026-11-22T00:00:00Z");
  assert.equal(H.tierFromEntitlements({ infinite_brain: { expires_date: "2026-12-01T00:00:00Z" } }, now), "Infinite Brain");
  assert.equal(H.tierFromEntitlements({ infinite_brain: { expires_date: "2026-11-01T00:00:00Z" }, creation_engine: { expires_date: null } }, now), "Creation Engine");
  assert.equal(H.tierFromEntitlements({}, now), "Free");
  assert.equal(H.isAnonymousRcId("$RCAnonymousID:abc"), true);
});

test("parseJsonLoose handles fenced and noisy output", () => {
  assert.deepEqual(H.parseJsonLoose('```json\n{"a":1}\n```'), { a: 1 });
  assert.deepEqual(H.parseJsonLoose('Here you go: [{"x":2}] thanks'), [{ x: 2 }]);
  assert.equal(H.parseJsonLoose("nope"), null);
});
