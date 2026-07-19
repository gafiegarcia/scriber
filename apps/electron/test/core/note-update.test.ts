import assert from "node:assert/strict";
import test from "node:test";
import { parseNoteUpdate } from "../../src/lib/core/note-update";
import { PATCH } from "../../src/app/api/notes/[id]/route";

test("note updates preserve title and tag editing", () => {
  assert.deepEqual(parseNoteUpdate({ title: "Renamed", tags: ["work"] }), {
    title: "Renamed",
    tags: ["work"],
  });
});

test("transcript content updates are rejected", () => {
  assert.throws(
    () => parseNoteUpdate({ content: "Rewritten transcript" }),
    /Transcript content and timing metadata are read-only/
  );
});

test("word timing metadata updates are rejected", () => {
  assert.throws(
    () => parseNoteUpdate({ metadata: { words: [] } }),
    /Transcript content and timing metadata are read-only/
  );
});

test("notes PATCH rejects transcript rewrites at the HTTP boundary", async () => {
  const response = await PATCH(
    new Request("http://127.0.0.1/api/notes/example", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content: "Rewritten transcript" }),
    }),
    { params: Promise.resolve({ id: "example" }) }
  );
  assert.equal(response.status, 400);
  assert.match((await response.json()).error, /read-only/);
});

test("unknown, empty, and malformed updates are rejected", () => {
  assert.throws(() => parseNoteUpdate({ createdAt: "tampered" }), /Unsupported note field/);
  assert.throws(() => parseNoteUpdate({}), /empty/);
  assert.throws(() => parseNoteUpdate({ title: " " }), /non-empty string/);
  assert.throws(() => parseNoteUpdate({ tags: ["valid", 42] }), /array of strings/);
});
