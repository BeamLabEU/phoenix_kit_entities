# Review — `0e84bab` "Stop the admin data form from flattening multilang data"

**Reviewer:** Claude
**Date:** 2026-07-29
**Author:** Root NaLazurke (`root@nalazurke.fr`), committed straight to `main` as
`0e84bab` — no PR
**Also in scope:** `61b2f86` "lib upgrades" (mix.lock only)
**Verdict:** Approve with one fix (applied) — the diagnosis and the fix are both
correct, but flipping the record load to raw left the *read* side of the same
data-loss path unpatched for exactly the state the commit itself identified on
the write side.

---

## Summary

`Web.DataForm.handle_params/3` loaded the record it was about to edit with
`EntityData.get!(uuid, lang: locale)`. `:lang` runs `resolve_language/2`, which
replaces the multilang `data` JSONB with `Multilang.get_language_data(data,
locale)` — a single merged map, with `_primary_language` and every other
language dropped from the struct. Since that same changeset is what
`merge_multilang_data/4` reads on save, every save wrote the collapsed map back.

Verified the chain rather than taking the message's word for it:

- `EntityData.maybe_resolve_lang/2` (`entity_data.ex:2738`) applies
  `resolve_language/2` whenever `:lang` is non-nil — there is **no**
  `Multilang.enabled?()` gate, so the flattening happened regardless of the
  Languages module's state.
- `Multilang.get_raw_language_data/2` (core) returns the *whole* map when
  `multilang_data?/1` is false, which is exactly what a flattened map looks
  like — so `MultilangForm.get_lang_data/3` really does hand every language tab
  the same content. The commit's account is accurate.
- `PhoenixKitEntities.resolve_language/2` (`phoenix_kit_entities.ex:1685`) only
  touches `display_name`, `display_name_plural`, and `description`. Keeping
  `:lang` on the *entity* load is therefore safe, as claimed —
  `fields_definition` is untouched.
- All other record loads in the module were already raw:
  `data_form.ex:317` (reset), `:770` (presence promotion), and every
  `EntityData.get!/1` in `data_navigator.ex`. The three sites the commit
  changed were the only leaks.

Everything above checks out. One finding.

---

## Findings

### BUG - HIGH — the single-language layout reads raw multilang data, renders every custom field blank, and saves the blanks over the primary language

`data_form.ex:1650` (pre-fix) — fixed in this review.

The commit reasoned carefully about the state where the Languages module is
**off** but the row still carries multilang `data` (languages configured once,
later switched off), and added `merge_lang/2` so the save merges under the row's
embedded `_primary_language` instead of a `null` key. That is the write side.
The read side has the same problem and was left alone:

- `multilang_enabled?/0` false ⇒ `show_multilang_tabs` false ⇒ the template
  takes the single-language branch, which calls
  `FormBuilder.build_fields(@entity, f, lang_code: nil)`.
- With `lang_code: nil`, `maybe_apply_language_view/3` is a no-op, so every
  field reads `FormBuilder.get_field_value/2` → `Map.get(data, field_key)`
  (`form_builder.ex:1274-1291`) **directly against the raw map**. A multilang
  row keeps its values one level down, under `data[primary]`, so every custom
  field renders blank.
- The browser then submits those blanks. `merge_lang/2` correctly targets the
  embedded primary, and `Multilang.put_language_data/3` **replaces** the primary
  language's map wholesale for the primary key — so the blank form is written
  over the primary language's real content.

Net effect at HEAD: open a multilang row in the admin with Languages disabled,
save, and the primary language's field values are gone. It is the same class of
loss the commit set out to stop, one state over.

Pre-existing, not introduced here: on a non-localized admin URL `locale` is nil,
so `maybe_resolve_lang/2` already skipped resolution and the fields already
rendered blank. What the commit changed is that this is now the behavior on
*every* URL, including the localized ones where flattening used to paper over
the blank render (while destroying the translations on save — the bug being
fixed). So the commit is still a net improvement; this just needs to land with
it.

The commit's own test would have caught it with one more assertion — the
fixture (`data_form_live_test.exs:33-42`) is precisely this state
(`en-US` holding `"name" => "Acme"`, Languages module off in the test env), and
"saving from the form leaves the other languages in the row" asserts
`_primary_language` and `es-ES` survive but never checks that `en-US` still
holds `"Acme"`. It does not.

**Fix applied.** `primary_language_view/1` in `data_form.ex` hands the
single-language layout a flattened primary-language view of the changeset to
read from. Field `name` attributes are unchanged, so the submitted params still
round-trip back under the primary key via `merge_lang/2` — the read side now
mirrors the write side. Flat rows are returned untouched, so the common case is
byte-identical. Locked by two tests in the new
`"single-language layout over a multilang row"` describe block: one asserting
`value="Acme"` renders, one asserting `data["en-US"]["name"]` survives a save.

### NITPICK — `_title` / `_slug` are dropped from the primary map when saving with Languages disabled

Not fixed, deliberately. In that state `validate_data/3` returns only the
entity's declared field keys (`inject_db_field_into_data/5` no-ops when
multilang is off), and `put_language_data/3` replaces the primary map, so
`_title`/`_slug` don't survive the save. Harmless in practice:
`get_title_translation/2` falls back to the `title` DB column
(`entity_data.ex:2601`), secondary-language overrides are stored independently
and are untouched, and `seed_translatable_fields/2` re-seeds `_title`/`_slug`
from the columns the next time the form mounts with multilang enabled. Fixing it
would mean special-casing underscore-prefixed keys inside the merge — more
machinery than the symptom warrants.

---

## Checked and clean

- **`merge_lang/2` key agreement.** It reads `socket.assigns.changeset`, the
  same changeset `merge_multilang_data/4` reads `existing_data` from, so the
  key it picks always matches the structure being merged into. No drift.
- **`merge_lang/2` guard ordering.** The `is_binary` clause wins whenever
  multilang is enabled (`mount_multilang/2` sets `current_lang` to
  `primary_language`, never nil in that state), so the fallback is genuinely
  reachable only in the languages-off case it documents.
- **Flat rows.** No `_primary_language` ⇒ `merge_lang/2` returns nil ⇒
  `do_merge_multilang_data/4`'s third branch passes params straight through,
  exactly as before. `primary_language_view/1` likewise returns the form
  unchanged. The overwhelmingly common path is untouched by both changes.
- **Re-key interaction.** When multilang *is* enabled, `rekey_data_on_mount/1`
  has already aligned the embedded primary with the global one, so
  `Multilang.get_primary_data/1` and `current_lang` agree.
- **`Components.LiveDataForm`.** Documents (`live_data_form.ex:413`) that its
  `record.data` is a flat map and merges over it directly; it never passes
  `:lang` to a record load. Out of scope, unaffected.
- **`mix.lock` bump (`61b2f86`).** `phoenix_kit` 1.7.216 → 1.7.220, plus
  `mdex`, `ranch`, `req` 0.6.3 → 0.7.1, `swoosh`. All transitive; nothing this
  module calls directly. Gate is green against them.

## Gate

`mix format`, then `mix precommit` (compile `--warnings-as-errors` + format
check + `credo --strict` + dialyzer) — green.

`mix test`: 385 tests, 0 failures, 589 excluded. No Postgres in this
environment, so the `:integration` tag auto-excluded the DB-backed tests —
including the four the commit added and the two added here. Per `AGENTS.md`
that is the documented stance for this repo; the gate, not `mix test`, is the
bar.
