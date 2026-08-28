"use strict";

// Unit tests for the pure slug rule inside the SlugFromTitle hook
// (priv/static/assets/phoenix_kit_entities.js). The hook writes the slug
// field as the title is typed so it feels instant; core still derives the
// slug it STORES, and the two must never visibly disagree.
//
// The bundle is browser code (an IIFE assigning onto `window`), so stub
// the globals it touches at load time. The DOM-using parts are not
// exercised here.
//
// Run: mix test.js

const test = require("node:test");
const assert = require("node:assert/strict");

global.window = {};
global.document = { querySelector: () => null, activeElement: null };

const { slugifyLatin } = require("../../priv/static/assets/phoenix_kit_entities.js");

test("plain Latin titles slugify the obvious way", () => {
  assert.equal(slugifyLatin("Oak Door"), "oak-door");
  assert.equal(slugifyLatin("  Matte   Finish  "), "matte-finish");
  assert.equal(slugifyLatin("50% Gloss!"), "50-gloss");
  assert.equal(slugifyLatin("---"), "");
  assert.equal(slugifyLatin(""), "");
});

test("accented Latin loses its marks rather than its letters", () => {
  assert.equal(slugifyLatin("Café"), "cafe");
  assert.equal(slugifyLatin("Tür Grün"), "tur-grun");
});

test("anything it cannot romanize is left to the server", () => {
  // Core's rule is locale-aware and romanizes ("Цвет" -> "tsvet"). This
  // returns "" rather than guessing, and the hook then writes nothing.
  assert.equal(slugifyLatin("Цвет"), "");
  assert.equal(slugifyLatin("色"), "");

  // MIXED scripts are the case worth pinning: dropping what it cannot
  // read would put "red" on screen for an instant, and the server's
  // "tsvet-red" would then replace it — a visible jump while typing.
  assert.equal(slugifyLatin("Цвет Red"), "");
});
