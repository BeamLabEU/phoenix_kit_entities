// phoenix_kit_entities JS hooks — folded into the host LiveSocket by
// core's :phoenix_kit_js_sources compiler (see PhoenixKit.Module.js_sources/0).
(function () {
  "use strict";

  window.PhoenixKitEntitiesHooks = window.PhoenixKitEntitiesHooks || {};

  // SlugFromTitle — fills the slug field as the title is typed, in the
  // browser, with no server round trip (Max, 2026-08-28: "it's just text
  // that doesn't need a server round trip").
  //
  // The server still derives the slug it will actually store: this is an
  // echo for the eye, not the source of truth. Two rules keep the two
  // from disagreeing on screen:
  //
  //   * It writes only while the server says the slug is still following
  //     the title (`data-slug-auto` on the target, mirrored from the
  //     LiveView's own flag). Once someone types their own slug, this
  //     goes quiet.
  //   * It writes only what it can slugify CONFIDENTLY — ASCII and
  //     accented Latin. Core's rule is locale-aware and romanizes
  //     Cyrillic ("Цвет" -> "tsvet"), which is not something to
  //     re-implement here; for anything this cannot handle it leaves the
  //     field alone and lets the server's value land.
  // Pure, and exported at the bottom of this file so `mix test.js` can
  // pin it: what this refuses to slugify is the whole contract between
  // the hook and core's locale-aware rule.
  function slugifyLatin(text) {
    // Combining marks: "é" -> "e". Anything without a Latin
    // decomposition (Cyrillic, Greek, CJK) survives this untouched.
    var latin = text.normalize("NFD").replace(/[̀-ͯ]/g, "");

    // Bail on ANY leftover non-ASCII, not just on an empty result.
    // Core romanizes ("Цвет Red" -> "tsvet-red"); dropping what this
    // cannot read would show "red" for an instant and then jump to the
    // server's answer. A mixed-script title is exactly where the two
    // disagree, so say nothing and let the server's value land.
    if (/[^\x00-\x7F]/.test(latin)) return "";

    return latin
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");
  }

  window.PhoenixKitEntitiesHooks.SlugFromTitle = {
    mounted() {
      this.onInput = () => this.mirror();
      this.el.addEventListener("input", this.onInput);
    },

    destroyed() {
      this.el.removeEventListener("input", this.onInput);
    },

    mirror() {
      // querySelector("") THROWS — an absent data-slug-target would take
      // the whole hook down rather than quietly doing nothing.
      var selector = this.el.dataset.slugTarget;
      if (!selector) return;

      var target = document.querySelector(selector);
      if (!target) return;

      // The server owns "is this still auto-generated?" — never guess it
      // from the field's contents, which lag a keystroke behind.
      if (target.dataset.slugAuto !== "true") return;

      // Don't fight the user if they happen to be in the slug field.
      if (document.activeElement === target) return;

      var slug = slugifyLatin(this.el.value || "");
      if (slug === "") return;

      target.value = slug;
    },

    slugify: slugifyLatin
  };

  if (typeof module === "object" && module.exports) {
    module.exports.slugifyLatin = slugifyLatin;
  }
})();
