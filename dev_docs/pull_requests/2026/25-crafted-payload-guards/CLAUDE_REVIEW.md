# PR #25 Review — guard entity data forms against crafted non-scalar payloads

**Reviewer:** Claude
**Date:** 2026-08-06
**Author:** Timujeen (`timujinne`), merged as `51ae446`
**Verdict:** Approve with fixes (applied) — the design is right and the
reasoning in the code comments is unusually good, but the whitelist it
introduces is one field type short of the registry, and the public,
un-authed caller it claims to cover crashes before ever reaching the gate
it relies on

---

## Summary

Three layers of shape-checking against crafted `data` payloads:

1. **`LiveDataForm` payload guards** — `when is_map(data_params)` on the
   `"autosave"`/`"submit"` clauses (a non-map `data_params` used to raise
   `BadMapError` inside `Map.get/3`, killing the whole LiveView process,
   not just the component), plus `extract_data_params/1` normalizing a
   present-but-non-map `"data"` value down to `%{}` (which used to raise
   the same way inside `normalize_absent_checkboxes/2`'s `Map.put_new/3`).
   Both malformed shapes now land on the same "treat as an empty autosave"
   clause that already handled an absent key.

2. **`LiveDataForm.sanitize_values/2`** — a per-field-type value-SHAPE gate
   running after `whitelist_known_fields/2` (which only filters by KEY).
   Scalar-only types drop non-scalars, `checkbox` filters its list down to
   binaries, `heading` drops unconditionally. A dropped key is simply
   absent from the merge, so the previously-stored value survives.

3. **`EntityData.changeset/2` shape guard** — `text`/`textarea`/`email`/
   `url`/`rich_text` now reject a non-scalar value outright instead of
   falling through the type-dispatch catch-all, and the `allow_other`
   escape hatch on `select`/`radio`/`checkbox` requires the custom value to
   be a binary (it previously accepted *any* term, maps included). This is
   the layer that also covers the admin `DataForm` and the public
   `EntityForm`, not just `LiveDataForm`.

Plus a genuinely nasty self-inflicted-crash fix in both `EntityData` and
`FormBuilder`: `Enum.join(invalid_values, ", ")` raised
`Protocol.UndefinedError` while building the very error message that
rejects a non-binary value — trading a stored bad value for an
attacker-triggered crash. Now `Enum.map_join/3` with a
`stringify_invalid_option/1` that falls back to `inspect/1`.

The threat model is real and correctly identified: `whitelist_known_fields/2`
never had an opinion on value shape, `FormBuilder.validate_type/2`'s
catch-all accepts any term, and `coerce_or_pass_through/3` uses that result
for best-effort coercion only — so a map could reach `record.data` under a
`text` key and then permanently break rendering for every subsequent viewer
(`to_string/1` in the readonly view, `{@value}` inside `<textarea>` in the
edit form). Verified against the emitters, not just the PR description.

## Findings

### 1. BUG — HIGH: the `file` field type is the one registry type both new whitelists miss, and it *is* rendered (fixed)

`@scalar_value_types` in `LiveDataForm` and the type dispatch in
`EntityData.validate_field_type/3` were cross-checked against
`FieldTypes.all/0`'s 13 types. Every type has an explicit rule in both
layers **except `file`**, which falls to each layer's catch-all:

| Layer | Clause reached by `file` |
|---|---|
| `LiveDataForm.sanitize_field_value/2` | `defp sanitize_field_value(_type, value), do: {:ok, value}` |
| `EntityData.dispatch_field_type_validation/4` | `_ -> changeset` |

The catch-all's comment justified this with *"Nothing in this component's
render paths naively stringifies their values the way the text-like types
above do."* That is not true for `file`:

- **Readonly view** — `file` has no `readonly_field/3` clause of its own,
  so it lands on the catch-all clause → `readonly_value/1` → `to_string/1`
  (`Protocol.UndefinedError` on a map) or `readonly_list/1` →
  `Enum.join/2` (same, for a list containing a map).
- **Edit form** — `FormBuilder.build_field/3`'s `file` clause iterates the
  stored value and indexes each entry (`file["filename"]`). The `is_list/1`
  check in front of it only constrains the container, not the elements: a
  list of plain strings reaches `"a.pdf"["filename"]`, which raises
  `FunctionClauseError` (Access has no binary clause).

Reachability is worse than for the types the PR did close. Nothing in this
library ever *produces* `file` data — the `build_field/3` clause is an
upload placeholder and nothing calls `consume_uploaded_entries/3` — so
every `file` value arrives from outside. And any non-`heading` field can be
added to `public_form_fields` (`Web.EntityForm`'s picker filters only
headings), so `data[attachment][]=x` on the **un-authed** POST at
`/entities/:entity_slug/submit` stores a list of strings that then breaks
the admin editor for that record, with no fix short of a manual DB edit.
That is precisely the stored DoS this PR set out to close.

**Fixed** in two places, matching the layer each problem belongs to:

- `LiveDataForm.sanitize_field_value/2` — explicit `:drop` clause for
  `file`/`image`/`relation`. None of them render a submittable input, so a
  value under their key can only be crafted; dropping is lossless for a
  parent app that populates them out of band, since a dropped key leaves
  `record.data`'s existing value untouched in the merge.
- `FormBuilder.build_field/3`'s `file` clause — `for file <- @current_files,
  is_map(file)`, so non-map entries are skipped and well-formed ones
  alongside them still render.

### 2. BUG — HIGH: the write-side gates are ingress-only; already-stored bad values still crash the readonly view (fixed)

Both new gates only govern what lands in `data` *from now on*. Three
populations of rows they can't help:

- rows poisoned before this PR (the exact rows its own comments describe as
  "un-fixable-without-a-DB-edit"),
- rows written by a parent app calling `EntityData` directly,
- anything under a `file` key (finding #1).

`LiveDataForm`'s readonly view is where those get rendered, and it had no
tolerance for them at all: `readonly_text/1` and `readonly_value/1` end in
a bare `to_string/1`, `readonly_list/1` in `Enum.join/2`. The
`select`/`radio` clause is worse — `FormBuilder.translated_option_label/3`
deliberately falls back to the **raw stored value** when it finds no
translation entry (that's the `allow_other` free-text case), so a map goes
straight into `{@display}` and raises via `Phoenix.HTML.Safe`.

Note the asymmetry the PR left behind: `EntityData` and `FormBuilder` both
got a `stringify_invalid_option/1` (`inspect/1` fallback) precisely so an
attacker-reachable interpolation can't raise — but the render surface those
functions exist to protect kept its raw `to_string/1`.

**Fixed** — `safe_string/1` in `LiveDataForm` (binary as-is, atom/number via
`to_string/1`, anything else via `inspect/1`), applied to `readonly_text/1`,
`readonly_value/1`, `readonly_list/1`'s join, and the `select`/`radio`
clause's `translated_option_label/3` result. Nothing rendered here is
load-bearing enough to be worth a crash. This is the layer that makes
already-poisoned rows viewable again.

### 3. BUG — MEDIUM: the public controller crashes on crafted payloads *before* the changeset gate it's said to rely on (fixed)

`EntityData.changeset/2`'s new guard is justified in-comment as covering
"the admin `DataForm` and the public `EntityForm` too". For the public
controller that only holds if the request reaches the changeset.
`EntityFormController.submit/2` is un-authed by design, so the entire body
is attacker-shaped and nested params (`a[b]=c`) arrive as maps — and four
spots trusted the shape, each producing an unhandled exception (a 500)
before `EntityData.create/2` ran:

| Spot | Crafted input | Raise |
|---|---|---|
| `get_in(params, ["phoenix_kit_entity_data", "data"])` | `phoenix_kit_entity_data=x` | `FunctionClauseError` (Access on a binary) |
| `FormBuilder.merge_other_params/2` | `phoenix_kit_entity_data[data][]=a` | no matching clause (`when is_map(params)`) |
| `generate_submission_title/2` → `generate_slug/1` | `data[title][x]=1` | `FunctionClauseError` (`String.downcase/1` on a map) |
| `get_time_to_submit/1` | `_form_loaded_at[x]=1` | `FunctionClauseError` (`DateTime.from_iso8601/1` on a map) |

The last one fires inside the security-check phase, i.e. on every public
submission with `public_form_time_check` on — the earliest reachable crash
on the endpoint.

**Fixed** — `extract_form_data/1` (pattern-matched, mirroring
`LiveDataForm.extract_data_params/1`'s contract: any malformed shape
degrades to "no fields submitted"), `generate_submission_title/2` now
accepts only a non-empty binary candidate and otherwise falls through to
`entity.display_name`, `get_time_to_submit/1` guards on `is_binary/1` and
treats anything else as "no timestamp provided", and the stored
`form_loaded_at` metadata goes through a new binary-or-nil
`cap_metadata_param/1` so a crafted map doesn't reach the JSONB column
either.

### 4. IMPROVEMENT — MEDIUM: `file` still has no shape opinion in the changeset (deliberately not fixed)

Finding #1 closes the `LiveDataForm` ingress and both render surfaces, but
`EntityData.changeset/2` still accepts any term under a `file` key. That is
intentional. This library never writes `file` data, so its stored shape is
defined entirely by whichever parent app populates it — a strict
`list-of-maps` gate here would be a guess, and it would reject data that
already works today. With the render paths made total (finding #2), storing
an odd term under a `file` key has no crash consequence, which is the part
that actually mattered. Recorded here so the gap is on the record rather
than rediscovered.

### 5. NITPICK: catch-all comment cites two types that aren't in the registry

The `sanitize_field_value/2` catch-all comment groups `file`/`image`/
`relation` together as field types. Only `file` is in `FieldTypes.all/0`;
`image` and `relation` have `build_field/3` render clauses but no registry
entry, so they can only come from a hand-edited `fields_definition`. The
replacement comment says so, and the new `:drop` clause covers all three
anyway.

### 6. Pre-existing (not from PR #25): `main`'s gate and test suite were both red

Two failures unrelated to this PR, both traceable to the `lib upgrades`
commit (`a88cbf3`) that landed just after the merge:

- **`mix precommit` failed at `deps.unlock --check-unused`** with eight
  orphaned lock entries (`igniter`, `sourceror`, `rewrite`, `spitfire`,
  `owl`, `glob_ex`, `ex_ast`, `text_diff`) — the dependency bump dropped
  them from the tree without pruning `mix.lock`. Same class as PR #24's
  finding #2 and PR #21's finding #1. Fixed with `mix deps.unlock --unused`.
- **Two `html_sanitizer_test.exs` failures** — the upgraded
  `PhoenixKit.Utils.HtmlSanitizer` now adds `rel="noopener noreferrer"` to
  links and inserts the implied `<tbody>` in tables. Both are upstream
  hardening / HTML-spec normalization, not regressions; the tests asserted
  byte equality against the dependency's old output. Rewritten to assert
  the properties that matter (element and safe attributes survive), so the
  next upstream bump doesn't break them again.

## What the PR got right (verified, not assumed)

- **The `is_map/1` guards fall through, not fail.** Confirmed the next
  matching clause in each pair is the existing `_params` fallback with the
  same `mode: :edit` requirement — a malformed payload becomes an empty
  autosave, not a crash and not a silent skip of
  `normalize_absent_checkboxes/2`.
- **`merge_other_params/2` can't be used to smuggle a shape past the
  sanitizer.** A crafted `<key>__other` value lands under the real field
  key *before* `whitelist_known_fields/2` and `sanitize_values/2` run, so
  select/radio still require a scalar and checkbox still filters to
  binaries. Ordering verified in `persist_data/3`.
- **The two `allow_other` fixes have the same effect through different
  shapes.** `EntityData.validate_checkbox_field/3` filters per element,
  `FormBuilder.validate_type/2` uses `Enum.all?/2` over `invalid_values` —
  different code, identical accept/reject outcome. Not drift.
- **`number`/`boolean` correctly stayed out of `@scalar_value_types`.**
  Their own clauses are narrower, and widening the group to the loosest
  member would have been the easy wrong call.
- **`@doc false` + `def` for `sanitize_values/2` / `extract_data_params/1`
  is justified.** Every path through `persist_data/3` ends at
  `EntityData.update/3`, which needs a live database, so these really are
  the only DB-free way to unit-test the rules.

## Tests added

- `live_data_form_test.exs` — new `:readonly` describe block covering
  already-stored non-scalars under `text`, `textarea`, `select`, `checkbox`
  and `file` (each renders, degraded, instead of raising); plus a
  `sanitize_values/2` case asserting `file`/`image`/`relation` values are
  dropped for every shape. All DB-free.
- `form_builder_render_test.exs` — `file` clause with well-formed metadata
  (renders the filename) and with mixed non-map entries (skips them, keeps
  the valid one).
- `entity_form_controller_test.exs` — new "crafted payloads" describe block
  with one test per crash site in finding #3, each asserting an ordinary
  redirect instead of a raise.
- `html_sanitizer_test.exs` — two assertions rewritten (finding #6).

## Gate

`mix precommit` — see `FOLLOW_UP.md`.
