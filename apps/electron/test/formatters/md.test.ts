import { test } from "node:test";
import assert from "node:assert/strict";

import { renderMarkdown } from "@/cli/formatters/md";

test("full frontmatter with all fields", () => {
  const out = renderMarkdown("Hello world.", {
    language: "en",
    languageProbability: 0.95,
    durationSeconds: 12.3,
    createdAt: "2026-04-25T10:00:00.000Z",
    title: "my-note",
  });
  assert.equal(
    out,
    [
      "---",
      "title: my-note",
      "language: en",
      "languageProbability: 0.95",
      "durationSeconds: 12.3",
      "createdAt: 2026-04-25T10:00:00.000Z",
      "---",
      "",
      "Hello world.",
      "",
    ].join("\n")
  );
});

test("omits durationSeconds when not provided", () => {
  const out = renderMarkdown("x", {
    language: "en",
    languageProbability: 0.9,
    createdAt: "2026-04-25T10:00:00.000Z",
  });
  assert.doesNotMatch(out, /durationSeconds/);
});

test("omits title when not provided", () => {
  const out = renderMarkdown("x", {
    language: "en",
    languageProbability: 0.9,
    createdAt: "2026-04-25T10:00:00.000Z",
  });
  assert.doesNotMatch(out, /^title:/m);
});

test("title with a colon is YAML-quoted", () => {
  const out = renderMarkdown("body", {
    title: "note: with colon",
    language: "en",
    languageProbability: 0.9,
    createdAt: "2026-04-25T10:00:00.000Z",
  });
  assert.match(out, /^title: "note: with colon"$/m);
});

test("title containing a double-quote is escaped", () => {
  const out = renderMarkdown("body", {
    title: 'say "hi"',
    language: "en",
    languageProbability: 0.9,
    createdAt: "2026-04-25T10:00:00.000Z",
  });
  assert.match(out, /^title: "say \\"hi\\""$/m);
});

test("body text is trimmed of surrounding whitespace", () => {
  const out = renderMarkdown("  \n\n  body text  \n\n  ", {
    language: "en",
    languageProbability: 0.9,
    createdAt: "2026-04-25T10:00:00.000Z",
  });
  assert.match(out, /---\n\nbody text\n$/);
});
