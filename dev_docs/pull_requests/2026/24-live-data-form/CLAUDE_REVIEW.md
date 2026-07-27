# PR #24 Review — heading field type, `allow_other` choice option, embeddable `LiveDataForm`

**Reviewer:** Claude
**Date:** 2026-07-24
**Author:** Tymofii Shapovalov (`timujinne`, `feature/live-data-form`), merged as `cc2f977`
**Verdict:** Approve with fixes (applied) — a real activity-log flood was reachable through the exact use case the PR describes as its motivation, plus an unrelated pre-existing `mix.lock` issue that had `main`'s gate red

---

## Summary

A large, additive PR (25 files, ~4,000 lines) shipping three features plus
validation hardening:

1. **`heading` field type** — display-only section header, correctly threaded
   through every place a field type is enumerated: `FieldTypes`, the entity
   changeset's type whitelist (now derived from `FieldTypes.list_types/0`
   instead of a hand-maintained `~w(...)` list — closes a "two lists must stay
   in sync" gap that had already drifted once), `FormBuilder.build_field/3`,
   `EntityData.changeset/2`'s per-field validator, and both `validate_data/3`
   branches.
2. **`allow_other` on select/radio/checkbox** — sentinel-based UI pattern
   (`"__other__"` + companion `<key>__other` text input), resolved by
   `FormBuilder.merge_other_params/2` before any validation/persistence path.
   Verified every write path (admin `DataForm`, public
   `EntityFormController`, `LiveDataForm`) calls `merge_other_params/2`
   *before* `FormBuilder.validate_data/3` or the changeset — `validate_data/3`'s
   own `select`/`radio` clauses don't reject the sentinel explicitly, so this
   ordering is load-bearing, not incidental; confirmed it holds everywhere.
3. **`PhoenixKitEntities.Components.LiveDataForm`** — embeddable
   `LiveComponent` for one record's fields, in `:edit` (autosave) or
   `:readonly` mode. Well-guarded: `resolve_entity/3` avoids a DB query on
   every re-render by reusing the caller's preloaded association or a cached
   socket assign; `handle_event/3` fails closed on anything but `mode: :edit`
   (a crafted `pushEventTo` against a `:readonly` instance's `cid` is
   otherwise reachable regardless of what the template renders); `render/1`
   mirrors the same fail-closed rule.

## Hardening that rides along

- `EntityData.changeset/2` now validates `radio`/`checkbox` against
  `options` (previously only `select` was checked), rejects the `__other__`
  sentinel unconditionally, rejects a non-list value for checkbox, and
  treats `[]` as missing for a *required* checkbox — aligning it with
  `FormBuilder.validate_required/2`, which already treated `value in [nil,
  "", []]` as absent.
- `EntityData.update/3` gains two new opt-in options: `activity_log: false`
  (skip the audit row for high-frequency autosave writes) and
  `require_status: [statuses]` (re-reads the row under `SELECT ... FOR
  UPDATE` inside a transaction and refuses the write if the fresh status
  isn't in the list — closes a real cross-session race where a stale
  `:edit` tab could overwrite a record another session had just
  transitioned). Both are additive, default to current behavior, and are
  correctly implemented — the status guard genuinely locks the row before
  checking, and builds the changeset against the freshly-read row rather
  than the caller's possibly-stale struct.

## Findings

### 1. BUG — HIGH: `activity_log: false` didn't suppress the error-path activity row, reopening exactly the flood it was built to prevent (fixed)

`lib/phoenix_kit_entities/entity_data.ex` — `EntityData.update/3`'s
`activity_log: false` option was wired only into the **success** path:

```elixir
defp notify_data_event({:ok, %__MODULE__{} = entity_data}, :updated, opts) do
  ...
  maybe_log_data_activity(entity_data, "entity_data.updated", opts)  # respects activity_log: false
  {:ok, entity_data}
end

defp notify_data_event({:error, _} = result, event, opts) do
  log_data_error_activity(event, opts)  # unconditional — ignored the opt
  result
end
```

The moduledoc for `activity_log: false` states its whole purpose: "used by
high-frequency callers (`LiveDataForm` autosave) so a client that's still
typing doesn't produce one activity row per debounced keystroke." But
`EntityData.changeset/2` re-validates **every required field across the
whole entity** on every single `update/3` call (this PR's own doc: "an
autosave attempt while any required field is still empty ... exactly like
any other save rejection"). Trace the PR's own motivating example — "a
client-facing equipment questionnaire" — which almost certainly has at
least one required field:

1. User opens the questionnaire via `LiveDataForm` in `:edit` mode; one
   required field is still blank.
2. User types into any *other* field. `phx-change` fires (debounced
   500ms) → `do_autosave/2` → `persist_data/3` → `EntityData.update/3`
   with `activity_log: false`.
3. `EntityData.changeset/2`'s required-field check fails (the blank
   required field) → `{:error, changeset}`.
4. `notify_data_event/3` matches the generic `{:error, _}` clause, which
   calls `log_data_error_activity/2` **unconditionally** — one
   `entity_data.updated` row with `db_pending: true` is inserted, actor
   included.
5. Repeat for every debounced keystroke until the required field is
   filled in — this is the exact "one activity row per debounced
   keystroke" scenario `activity_log: false` exists to prevent, just
   reached through the failure path instead of the success path.

No test exercised this path — `activity_logging_test.exs`'s
`activity_log: false` test and both `live_data_form_test.exs`/
`live_data_form_integration_test.exs` files only use entities without
required fields, so the gap was never observed.

No entity_data row is corrupted (the changeset failure means
`repo().update/1` is never reached — the underlying record is untouched),
but the `phoenix_kit_activities` table takes one write per debounced
keystroke for the whole duration a user fills out a form with any
required field — meaningful DB write amplification and audit-log noise on
exactly the surface (a public-facing multi-field questionnaire) this
feature targets.

**Fix applied.** `notify_data_event({:error, _}, event, opts)` now checks
`Keyword.get(opts, :activity_log, true)` before calling
`log_data_error_activity/2`, mirroring `maybe_log_data_activity/3`'s guard
on the success path. Added a regression test —
*"update {:error, _} with activity_log: false also skips the error row
(LiveDataForm autosave against an incomplete required field must not
flood the log)"* — to `activity_logging_test.exs`, using an entity with a
`required: true` field and asserting both that the opt suppresses the row
and that a follow-up call without the opt still logs normally (matching
the existing test's shape for the success path).

## Non-issues considered

- **`FormBuilder.validate_type/2`'s `select`/`radio` clauses don't reject
  the `__other__` sentinel explicitly** (unlike `EntityData.changeset/2`'s
  `validate_choice_field/3`, which does) — verified every caller of
  `FormBuilder.validate_data/3` (`Web.DataForm`, `Components.LiveDataForm`,
  `EntityFormController`) calls `merge_other_params/2` first, so the
  sentinel never reaches `validate_type/2` in practice. Worth keeping in
  mind if a new caller of `validate_data/3` is ever added without the
  `merge_other_params/2` step first, but not a live bug today.
- **`persist_statuses`/`require_status` don't provide optimistic locking on
  `data`** — explicitly documented in both the `LiveDataForm` moduledoc and
  the PR description as a deliberate scope boundary (status-transition
  guard only, not concurrent-edit protection). Confirmed the guard does
  what it claims: it locks the row (`FOR UPDATE`), re-checks status against
  the fresh read, and builds the changeset off the fresh row — the
  documented gap (two sessions racing within the *same* allowed status)
  is real but out of scope by design, not an oversight.
- **`heading` fields excluded from validation/storage in four separate
  places** (`EntityData.changeset/2`, both `FormBuilder.validate_data/3`
  branches, and implicitly by never rendering an input) — this is
  necessarily repeated per call site rather than a single choke point
  given the existing architecture (changeset validation and form-param
  validation are separate systems); traced each one and they agree.
- **`FieldTypes.allow_other?/1`'s string/boolean tolerance** (`"true"` vs
  `true`) — correctly justified by the moduledoc: field definitions are
  submitted from HTML forms (checkbox values arrive as strings) and
  persisted as-is into JSONB, so comparing against the literal `true`
  would silently fail for every definition created through the admin UI.
  Verified this tolerance is applied consistently everywhere `allow_other`
  is read (`FormBuilder.build_field/3`'s select/radio/checkbox clauses,
  `merge_other_params/2`, `EntityData`'s `validate_choice_field/3` and
  `validate_checkbox_field/3`).

### 2. BUG — HIGH (pre-existing, not from this PR): stale `mix.lock` entry broke `mix precommit` on `main` (fixed)

Unrelated to PR #24 itself but discovered while running its gate: the
`lib upgrades` commit (`2bf51d1`, already on `main`) left a stale,
orphaned lock entry — `"beamlab_ex_aws_sqs"` at `4.0.0` — alongside the
correct one (keyed `"ex_aws_sqs"`, pointing at the same Hex package
`beamlab_ex_aws_sqs` at `5.0.0`, matching `phoenix_kit`'s own
`{:ex_aws_sqs, "~> 5.0", [hex: :beamlab_ex_aws_sqs, ...]}` dependency
declaration). Nothing in the resolved dependency tree references the app
name `:beamlab_ex_aws_sqs` directly anymore, so `mix deps.unlock
--check-unused` (part of `mix precommit`) failed with "Unused
dependencies in mix.lock file: * :beamlab_ex_aws_sqs" — the gate was red
on `main` before this batch, the same class of issue the PR #21 review
found and fixed (a post-merge "lib upgrades" commit breaking the gate).

**Fix applied.** `mix deps.unlock beamlab_ex_aws_sqs` removes the
orphaned entry; the correct `"ex_aws_sqs"` entry (5.0.0) is untouched.
`mix precommit` passes clean after the fix.

## Validation

Authoritative gate: `mix precommit` (`compile --force --warnings-as-errors`
+ `deps.unlock --check-unused` + `hex.audit` + `quality.ci` = `format
--check-formatted` + `credo --strict` + `dialyzer`).

- `compile --force --warnings-as-errors`: clean
- `deps.unlock --check-unused`: clean (red before finding #2's fix)
- `hex.audit`: no retired/security-advisory packages
- `format --check-formatted`: clean
- `credo --strict`: no issues (86 files, 1251 mods/funs)
- `dialyzer`: **0 errors**

`mix test` could not run in this sandbox — `test_helper.exs` calls
`System.cmd("psql", ["-lqt"], ...)` unconditionally to probe for a test
database, and `System.cmd` raises `:enoent` (rather than returning a
non-zero-exit tuple the surrounding `case` could fall back on) when the
`psql` binary itself isn't installed, so the whole suite aborts at load
time before any exclusion logic runs. Same class of gap as the PR #20/#21
reviews in this repo ("`psql` client is not installed"). Out of scope for
this PR's review — a pre-existing sandbox limitation, not something #24
introduced.
