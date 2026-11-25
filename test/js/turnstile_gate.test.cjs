"use strict";

// Unit tests for the Turnstile helpers in the bundle
// (priv/static/assets/phoenix_kit_entities.js): when a submit has no token yet
// and which widgets belong to a LiveView (and so to core's hook).
//
// The bundle is browser code, so the globals it touches at load time are
// stubbed and the helpers are fed plain objects.
//
// Run: mix test.js

const test = require("node:test");
const assert = require("node:assert/strict");

global.window = {};
global.document = { querySelector: () => null, activeElement: null };

const { tokenMissing, insideLiveView, guardSubmit } = require("../../priv/static/assets/phoenix_kit_entities.js");

const formWith = (field, gate = true) => ({
  hasAttribute: (name) => gate && name === "data-turnstile-gate",
  querySelector: (selector) => {
    if (selector === '[name="cf-turnstile-response"]') return field;
    if (selector === "[data-turnstile-gate-message]") return formWith.message;
    return null;
  }
});

test("a submit has no token when the field is absent, empty or blank", () => {
  assert.equal(tokenMissing(formWith(null)), true);
  assert.equal(tokenMissing(formWith({ value: "" })), true);
  assert.equal(tokenMissing(formWith({ value: "   " })), true);
  assert.equal(tokenMissing(formWith({ value: undefined })), true);
});

test("a submit with a token is left alone", () => {
  assert.equal(tokenMissing(formWith({ value: "0.abc" })), false);
});

test("an element belongs to a LiveView when it sits under a LiveView container", () => {
  assert.equal(insideLiveView({ closest: (s) => (s === "[data-phx-session]" ? {} : null) }), true);
  assert.equal(insideLiveView({ closest: () => null }), false);
  assert.equal(insideLiveView({}), false);
});

test("guardSubmit stops a tokenless submit and shows the message, keeping the page", () => {
  formWith.message = { hidden: true };
  let prevented = false;
  guardSubmit({ target: formWith({ value: "" }), preventDefault: () => (prevented = true) });
  assert.equal(prevented, true);
  assert.equal(formWith.message.hidden, false);
});

test("guardSubmit lets a submit with a token, or a form without the gate, through", () => {
  let prevented = false;
  const event = (form) => ({ target: form, preventDefault: () => (prevented = true) });

  guardSubmit(event(formWith({ value: "0.abc" })));
  guardSubmit(event(formWith({ value: "" }, false)));
  guardSubmit(event({}));
  guardSubmit(event(null));

  assert.equal(prevented, false);
});
