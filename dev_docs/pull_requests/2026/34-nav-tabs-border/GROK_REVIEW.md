# Grok Review — PR #34 "Use core nav_tabs for the import preview entity tabs"

**Merge commit:** 7989505
**Author:** mdon (`fix/nav-tabs-border`)
**Files:** `lib/phoenix_kit_entities/web/entities_settings.ex`,
`test/phoenix_kit_entities/web/entities_settings_live_test.exs`

## Summary of the change

The import-preview entity strip was a hand-rolled `tabs tabs-border` row of
buttons sending `phx-value-entity`. It now uses core's
`<.nav_tabs variant={:border}>`, so the daisyUI class lives in one place and
the payload key moves to the component's standard `tab`. The LiveView
handler and the existing `render_hook` in the live test both follow.

Companion to BeamLabEU/phoenix_kit#746 (`variant={:border}` / verbatim
`:patch`). `mix.lock` is on `phoenix_kit` 2.13.6, which is the first core
release that admits `:border` on the attr whitelist.

## Findings

### IMPROVEMENT - MEDIUM: the live test never rendered `<.nav_tabs>`

The only test that moved with the payload-key rename is a crash-don't-crash
`render_hook` of `set_import_tab`. `show_import_modal` calls
`Importer.preview_import/0`, which lists JSON files under the mirror root.
The settings live test never writes any, so the preview is empty, the
`length(@import_preview.entities) > 0` branch is skipped, and
`variant={:border}` is never exercised.

That matters because `nav_tabs`' `attr :variant, values: [:boxed, :plain, :border]`
raises at render time on an older core. The PR body said CI would stay red
against Hex 2.13.5 until core landed; against an empty preview it would stay
green. A mismatch between the handler's `%{"tab" => _}` and a leftover
`phx-value-entity` would also have been invisible — `render_hook` injects the
map directly and never clicks the component.

**Fixed** — added
`"import preview entity tabs render via nav_tabs and switch on phx-value-tab"`
which writes two mirror JSON files, opens the modal, asserts `tabs-border` +
`phx-click="set_import_tab"` + `phx-value-tab`, then `render_click`s the
second tab and checks `tab-active` moved. Cleanup via `Storage.delete_entity/1`.

## Verified, no change needed

- **Handler / template / test triple.** The only `set_import_tab` emitter is
  this strip. `nav_tabs` dispatches `phx-value-tab` (documented: the key is
  deliberately not configurable because LiveView's `extractMeta` would
  otherwise overwrite `meta.value` with the button's empty `.value`). No
  leftover `phx-value-entity` on the tab buttons; the nearby
  `do_import_entity` button still uses `phx-value-entity` for a different
  event, correctly.
- **`import_active_tab` is a string.** It is `entity.name` from the
  preview (filename stem), matching `attr :active_tab, :string`. The strip
  only renders when `preview.entities` is non-empty, so `nil` never reaches
  the required attr.
- **Badge contract.** `badge: length(entity.data)` matches the old
  `length(entity.data)` span. Zero still renders (core: "Zero still
  renders"); inactive badges drop `badge-ghost` for the component default,
  active stays `badge-primary` — the PR called this out.
- **Queries stay out of `mount/3`.** Preview is loaded in the
  `show_import_modal` event. `mount` only assigns empties and subscribes.
- **Core floor vs `~> 2.0`.** `variant={:border}` needs phoenix_kit 2.13.6.
  mix.exs stays `~> 2.0` because `CorePinConformanceTest` forbids a floor
  that rejects 2.0.x / 2.1.x — a host on 2.13.5 that opened a non-empty
  import modal would hit the attr `values:` raise. That's the documented
  ecosystem sequencing ("merge core first"), not a pin we can tighten.
