import { test } from "node:test";
import assert from "node:assert/strict";

import { renderSrt } from "@/cli/formatters/srt";
import type { ScribeWord } from "@/lib/types/elevenlabs";

function word(text: string, start: number, end: number): ScribeWord {
  return { text, start, end, type: "word" };
}
function space(start: number, end: number): ScribeWord {
  return { text: " ", start, end, type: "spacing" };
}
function punct(text: string, start: number, end: number): ScribeWord {
  return { text, start, end, type: "punctuation" };
}

test("empty word list produces empty SRT", () => {
  assert.equal(renderSrt([]), "");
});

test("single-word cue uses its own start/end and has index 1", () => {
  const out = renderSrt([word("Hello", 0.5, 1.25)]);
  assert.match(out, /^1\n00:00:00,500 --> 00:00:01,250\nHello\n$/);
});

test("7-word cap flushes exactly after the 7th word", () => {
  const words: ScribeWord[] = [];
  for (let i = 0; i < 7; i++) {
    words.push(word(`w${i}`, i * 0.2, i * 0.2 + 0.15));
    if (i < 6) words.push(space(i * 0.2 + 0.15, (i + 1) * 0.2));
  }
  // 8th word must spill into cue 2
  words.push(space(1.4, 1.5));
  words.push(word("w7", 1.5, 1.7));

  const out = renderSrt(words);
  const blocks = out.trim().split(/\n\n/);
  assert.equal(blocks.length, 2, "expected exactly 2 cues");
  assert.match(blocks[0], /^1\n/);
  assert.match(blocks[1], /^2\n/);
  // Cue 1 text has 7 tokens joined with single spaces
  const cue1Text = blocks[0].split("\n").slice(2).join(" ");
  assert.equal(cue1Text, "w0 w1 w2 w3 w4 w5 w6");
  const cue2Text = blocks[1].split("\n").slice(2).join(" ");
  assert.equal(cue2Text, "w7");
});

test("5-second cap flushes early even when word count is low", () => {
  // 3 slowly-spoken words spanning > 5s → must split
  const words: ScribeWord[] = [
    word("one", 0, 2.5),
    space(2.5, 2.6),
    word("two", 2.6, 5.2), // cue 1 spans 5.2s at this point → flush
    space(5.2, 5.3),
    word("three", 5.3, 6.0),
  ];
  const out = renderSrt(words);
  const blocks = out.trim().split(/\n\n/);
  assert.equal(blocks.length, 2, "slow speech should split into 2 cues");
});

test("punctuation doesn't count toward word cap", () => {
  // 7 real words + punctuation interleaved — all must fit in one cue
  const words: ScribeWord[] = [];
  for (let i = 0; i < 7; i++) {
    words.push(word(`w${i}`, i * 0.3, i * 0.3 + 0.2));
    words.push(punct(",", i * 0.3 + 0.2, i * 0.3 + 0.25));
    if (i < 6) words.push(space(i * 0.3 + 0.25, (i + 1) * 0.3));
  }
  const out = renderSrt(words);
  const blocks = out.trim().split(/\n\n/);
  assert.equal(blocks.length, 1, "punctuation should not push past the word cap");
});

test("timestamp format: HH:MM:SS,mmm with zero-padding", () => {
  const out = renderSrt([word("x", 3661.007, 3661.5)]); // 1h 1m 1.007s
  assert.match(out, /01:01:01,007 --> 01:01:01,500/);
});

test("spacing tokens between words are collapsed to single spaces", () => {
  const out = renderSrt([
    word("hi", 0, 0.3),
    space(0.3, 0.4),
    space(0.4, 0.5), // double spacing token
    word("there", 0.5, 0.8),
  ]);
  assert.match(out, /\nhi there\n/);
});

test("cue numbers increment monotonically across many cues", () => {
  const words: ScribeWord[] = [];
  // 14 words → 2 cues
  for (let i = 0; i < 14; i++) {
    words.push(word(`w${i}`, i * 0.2, i * 0.2 + 0.15));
    if (i < 13) words.push(space(i * 0.2 + 0.15, (i + 1) * 0.2));
  }
  const out = renderSrt(words);
  const indices = out
    .split("\n")
    .filter((line) => /^\d+$/.test(line))
    .map((s) => Number(s));
  assert.deepEqual(indices, [1, 2]);
});
