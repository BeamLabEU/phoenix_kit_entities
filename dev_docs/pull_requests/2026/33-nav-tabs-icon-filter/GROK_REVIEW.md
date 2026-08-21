# Grok Review — PR #33 "Use core's nav_tabs for the icon category filter, and fix the daisyUI tabs class"

**Merge commit:** f4c2021
**Author:** mdon (fix/daisyui-tabs-box)
**Files:** `lib/phoenix_kit_entities/web/entity_form.ex`, `test/phoenix_kit_entities/web/entity_form_live_test.exs`

## Summary of the change

The icon-picker category strip was a hand-rolled `tabs tabs-boxed` row of
buttons sending `phx-value-category`. It now uses core's `<.nav_tabs>`, so
the daisyUI class lives in one place and the payload key moves to the
component's standard `tab`. The LiveView handler and the existing
`render_hook` in the live test both follow.

`selected_category` is already a string (`"All"` / Heroicon category
names), which matches `nav_tabs`' `active_tab` attr.

## Findings

None. The handler/template/test triple stays in sync. No other emitter of
`filter_by_category` exists.
