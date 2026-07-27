# Follow-up Items for PR #24

Triaged against `main` on 2026-07-24. CLAUDE_REVIEW raised 2 findings; both
are fixed in this batch.

## Fixed (2026-07-24)

- ~~**#1** `activity_log: false` didn't suppress the error-path activity
  row~~ — `lib/phoenix_kit_entities/entity_data.ex`. `notify_data_event`'s
  generic `{:error, _}` clause called `log_data_error_activity/2`
  unconditionally, ignoring the `activity_log` opt that the success path
  already respected. Since `EntityData.changeset/2` re-validates every
  required field on every `update/3` call, a `LiveDataForm` autosave
  against an entity with an unfilled required field (the PR's own
  "equipment questionnaire" motivating use case) inserted one
  `db_pending: true` activity row per debounced keystroke — exactly the
  flood `activity_log: false` was built to prevent, just reached through
  the failure path instead of the success path. Fixed by gating
  `log_data_error_activity/2` on the same `Keyword.get(opts, :activity_log,
  true)` check as the success path. Added a regression test to
  `activity_logging_test.exs` using an entity with a `required: true`
  field, asserting the opt suppresses the error row and that a follow-up
  call without the opt still logs normally.

- ~~**#2** (pre-existing, not from PR #24) stale `mix.lock` entry broke
  `mix precommit` on `main`~~ — `mix.lock`. The `lib upgrades` commit
  (`2bf51d1`, already merged) left an orphaned `"beamlab_ex_aws_sqs"`
  4.0.0 lock entry alongside the correct `"ex_aws_sqs"` 5.0.0 entry (same
  underlying Hex package, aliased), so `mix deps.unlock --check-unused`
  failed with "Unused dependencies in mix.lock file: *
  :beamlab_ex_aws_sqs" — the gate was red on `main` before this batch,
  same class of issue as the PR #21 review's finding #1. Fixed with `mix
  deps.unlock beamlab_ex_aws_sqs`.

## Open

None.

## Gate

`mix precommit` (`compile --force --warnings-as-errors` + `deps.unlock
--check-unused` + `hex.audit` + `format --check-formatted` + `credo
--strict` + `dialyzer`) passes clean after both fixes: 0 compile
warnings, 0 unused locks, no retired/advisory packages, formatted, 0
credo issues (86 files), 0 dialyzer errors.

`mix test` could not run in this sandbox: `test_helper.exs` calls
`System.cmd("psql", ...)` unconditionally, which raises `:enoent` (rather
than falling back to "DB unavailable") when the `psql` binary itself
isn't installed — the whole suite aborts at load time. Same environment
gap as the PR #20/#21 reviews in this repo; out of scope here.
