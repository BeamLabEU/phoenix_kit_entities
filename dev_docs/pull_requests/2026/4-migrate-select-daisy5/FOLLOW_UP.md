# Follow-up Items for PR #4

Triaged against `main` on 2026-04-25. Single nit; fixed in this sweep.

## Fixed (Batch 1 — 2026-04-25)

- ~~**Nit** Inconsistent label/select indentation in
  `entities_settings.ex`~~ — both wrapper sites
  (`entities_settings.ex:1164-1195` definition action select and
  `entities_settings.ex:1277-1321` per-record action select) had the
  inner `<select>` flush-left against the surrounding `<label>` instead
  of indented one level. Re-indented both blocks so the `<select>` and
  its `<option>` children sit inside the `<label>` wrapper, matching
  the other 13 select sites migrated in this PR. `mix format` re-ran
  cleanly afterward.

## Files touched

| File | Change |
|------|--------|
| `lib/phoenix_kit_entities/web/entities_settings.ex` | Re-indented two `<label class="select select-...">` blocks so the inner `<select>`/`<option>` markup sits one level deeper, matching the rest of the PR |

## Verification

- `mix format --check-formatted` ✓ (re-formatted file is clean)
- `mix compile --warnings-as-errors` ✓
- Behavior unchanged — pure whitespace adjustment inside heex templates.

## Open

None.
