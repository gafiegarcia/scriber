import { test } from "node:test";
import assert from "node:assert/strict";

import { renderJson, type JsonOutputPayload } from "@/cli/formatters/json";

function samplePayload(): JsonOutputPayload {
  return {
    text: "Hello world.",
    language_code: "en",
    language_probability: 0.98,
    words: [{ text: "Hello", start: 0, end: 0.5, type: "word" }],
    id: "abc-123",
    noteId: null,
    outputs: [],
    createdAt: "2026-04-25T10:00:00.000Z",
  };
}

test("output is valid JSON and round-trips", () => {
  const out = renderJson(samplePayload());
  const parsed = JSON.parse(out);
  assert.equal(parsed.text, "Hello world.");
  assert.equal(parsed.id, "abc-123");
  assert.equal(parsed.noteId, null);
  assert.equal(parsed.words.length, 1);
});

test("output is pretty-printed with 2-space indent", () => {
  const out = renderJson(samplePayload());
  assert.match(out, /\n  "text":/);
  assert.match(out, /\n  "words":/);
});

test("ends with a trailing newline", () => {
  const out = renderJson(samplePayload());
  assert.ok(out.endsWith("\n"), "stdout-friendly trailing newline expected");
});

test("required contract fields are always present", () => {
  const out = renderJson(samplePayload());
  const parsed = JSON.parse(out);
  for (const key of [
    "text",
    "language_code",
    "language_probability",
    "words",
    "id",
    "noteId",
    "outputs",
    "createdAt",
  ]) {
    assert.ok(key in parsed, `missing field: ${key}`);
  }
});
