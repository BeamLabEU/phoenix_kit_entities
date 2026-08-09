# Follow-up Items for `0e84bab`

Triaged against `main` on 2026-07-29. CLAUDE_REVIEW raised 1 bug and
1 nitpick; the bug is fixed in this batch, the nitpick is closed as
won't-fix with rationale.

## Fixed (2026-07-29)

- ~~**#1 BUG - HIGH** the single-language layout read raw multilang data,
  rendered every custom field blank, and saved the blanks over the primary
  language~~ — `lib/phoenix_kit_entities/web/data_form.ex`. With the Languages
  module off but the row still carrying multilang `data`, the template takes
  the single-language branch and calls `FormBuilder.build_fields/3` with
  `lang_code: nil`, so every field reads `Map.get(data, field_key)` against the
  raw map — one level above where a multilang row keeps its values. Fields
  rendered blank, and since `merge_lang/2` (added by `0e84bab` itself) merges
  the submitted params under the row's embedded `_primary_language`, the next
  save replaced that language's real content with the blanks. Same data loss
  the commit set out to fix, one state over; `0e84bab` patched the write side
  of it and left the read side. Fixed with `primary_language_view/1`, which
  hands the single-language layout a flattened primary-language view of the
  changeset to read from. Input `name` attributes are unchanged, so params
  still round-trip back under the primary key — read side now mirrors the write
  side. Flat rows pass through untouched. Locked by a new
  `"single-language layout over a multilang row"` describe block in
  `data_form_live_test.exs`: one test asserts `value="Acme"` renders, one
  asserts `data["en-US"]["name"]` survives a save. The fixture `0e84bab`
  already added is exactly this state, so the second test fails without the
  fix.

## Won't fix

- **#2 NITPICK** `_title` / `_slug` are dropped from the primary language map
  when saving with Languages disabled. `validate_data/3` returns only the
  entity's declared field keys in that state and `put_language_data/3` replaces
  the primary map, so the two underscore keys don't survive. Harmless and
  self-healing: `get_title_translation/2` falls back to the `title` column,
  secondary-language overrides are stored independently and are untouched, and
  `seed_translatable_fields/2` re-seeds both from the columns the next time the
  form mounts with multilang on. A fix would mean special-casing
  underscore-prefixed keys inside the merge — more machinery than the symptom
  warrants.

## Open

None.

## Gate

`mix format` + `mix precommit` (compile `--warnings-as-errors`, format check,
`credo --strict`, dialyzer) — green.

`mix test`: 385 passing, 0 failures, 589 excluded. No Postgres in this
environment, so `:integration` auto-excluded the DB-backed tests, including the
four `0e84bab` added and the two added here. Per `AGENTS.md` the gate is the
bar for this repo, not `mix test`.

Released as `0.2.10`.
