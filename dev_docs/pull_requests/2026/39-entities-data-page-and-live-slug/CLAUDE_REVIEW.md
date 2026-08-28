# PR #39 Review — Make the data page client-readable, and derive the slug in the browser

**Reviewer:** Claude
**Date:** 2026-08-28
**Verdict:** Approve (1 nitpick fixed)

---

## Summary

Three mostly-independent changes bundled together:

1. **Data Navigator page redesign** — collapses four always-shown stat cards
   into a filter row of status chips (`show_filters?/1` hides the whole card
   on an empty, unfiltered, brand-new entity), and adds new batched
   `EntityData` query helpers (`list_by_entities/2`, `counts_by_entities/2`,
   `entity_uuids_matching_title/3`) so a listing over many entities runs a
   constant number of queries instead of one (or two) per entity.
2. **Live client-side slug echo** — a new `phoenix_kit_entities.js` hook
   (`SlugFromTitle`, registered via `js_sources/0`) mirrors the slug field
   from the title as-you-type, with the server remaining the source of
   truth. Slug "ownership" (auto vs. user-typed) is tracked server-side via
   `slug_auto?`, driven off `_target` in the `validate` event — not
   re-derived from the posted slug value, which is what caused the
   pre-fix version to freeze after the first keystroke once debounce went
   to 0 (documented in-line at `track_slug_ownership/3`).
3. **Managed blueprints get first-class editing** — `web/entities.ex` drops
   `include_managed: false` from all 5 `list_entities/1` call sites
   (verified no site was missed — the exact bug class PR #31's own
   follow-up had to patch twice), replacing the earlier "hide managed
   blueprints from the generic admin" policy with a "show them, badge them,
   lock only the structural fields" policy. `EntityForm` disables
   slug/status for a managed blueprint and pairs each disabled control with
   a hidden twin carrying its current value (a `disabled` control is
   dropped from `FormData` entirely, so without the twin a save would
   silently blank/desync the field) — confirmed against
   `PhoenixKitEntities.Managed.owner/1`, which is nil-safe for a
   settings-less/new entity.
4. A media picker (Choose/Clear) wired into `FormBuilder.build_field/3` for
   `image`/`video` fields, using the same
   `"#{schema_source}[data][#{key}]"` hidden-input naming convention every
   other field type in that module already uses.

## Issues Found

### NITPICK — stale test filename in comment (fixed)

`entity_data.ex`'s `sort_rows/2` doc comment pointed at
`list_by_entities_test.exs`, which doesn't exist — the actual coverage
(`"order matches list_by_entity, in both sort modes"`) lives in
`entity_data_batch_counts_test.exs`. Fixed the comment to name the real
file.

## Things checked that turned out fine (worth recording so a future
reviewer doesn't re-walk the same path)

- **`sort_rows/2`'s Elixir-side "manual" sort vs. `sort_order_for_mode/1`'s
  SQL `[asc_nulls_last: :position, desc: :date_created]`**: the batch
  version's `{is_nil(pos), pos, inverted_date(date_created)}` tuple key
  reproduces nulls-last-on-position and desc-on-date correctly. `nil`
  `date_created` would sort differently between the two (SQL `DESC`
  defaults to `NULLS FIRST`; the Elixir tuple sorts a `nil` inverted-date
  last) — but `date_created` is `NOT NULL DEFAULT now()` at the DB level
  (`phoenix_kit/migrations`, `V.column:phoenix_kit_entity_data.date_created`),
  so this is dead code, not a live divergence.
- **The `translatable_field` extra dynamic attrs
  (`live_debounce/0`/`slug_mirror_attrs/0`) not being declared attrs of the
  currently-pinned core's `translatable_field`**: confirmed
  `deps/phoenix_kit`'s `multilang_form.ex` has no `:global`/rest-attrs
  catch-all yet, so `phx-hook`/`data-slug-target`/`phx-debounce` passed
  this way are silently dropped today — exactly the "graceful degradation"
  the in-line comment says to expect until a newer core release adds the
  spread. Not a bug; the server-side slug generation (the part that
  matters for correctness) doesn't depend on it.
- **`entity_uuids_matching_title/3`'s raw SQL fragment** — `pattern` is
  bound via `^pattern`, not interpolated (no SQL injection); `escape_like/1`
  escapes `\`, then `%`, then `_`, in the order that avoids double-escaping.
- **Hidden media-picker input naming** — matches the
  `"#{changeset.data.__struct__.__schema__(:source)}[data][#{field["key"]}]"`
  convention used by every other `build_field` clause in `form_builder.ex`.
- **`managed_blueprint?/1`'s hidden `entities[name]` twin** — the visible
  "Slug" field is `field_name="name"`/`schema_field={:name}` (entities are
  named by `:name`, not `:slug` — that's the `EntityData` record field),
  so the hidden input's `name="entities[name]"` is correct, not a
  mismatch.
- **`js_sources/0` shape** — matches
  `PhoenixKit.Module.js_sources/0`'s `%{app:, file:, global:}` callback
  contract, the hook's global name (`PhoenixKitEntitiesHooks`) is namespaced
  (no collision with core hooks), and `mix.exs`'s `package[:files]` already
  ships all of `priv` (not just `priv/entities`, which is
  `exclude_patterns`-only), so `priv/static/assets/phoenix_kit_entities.js`
  actually reaches Hex consumers.
- **`mix.exs`'s new `test.js` alias** — skips (not fails) when `node` is
  absent or `test/js/*.test.cjs` is empty, and is wired into `precommit`
  after `quality.ci`.

## Post-Review Status

No blockers. `mix precommit` run as the release gate (see FOLLOW_UP.md).
