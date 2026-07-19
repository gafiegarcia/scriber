import { test } from "node:test";
import assert from "node:assert/strict";

import { renderTxt } from "@/cli/formatters/txt";

test("adds trailing newline when missing", () => {
  assert.equal(renderTxt("hello"), "hello\n");
});

test("preserves existing trailing newline", () => {
  assert.equal(renderTxt("hello\n"), "hello\n");
});

test("empty string still gets a newline", () => {
  assert.equal(renderTxt(""), "\n");
});

test("interior newlines are preserved", () => {
  assert.equal(renderTxt("a\nb\nc"), "a\nb\nc\n");
});
