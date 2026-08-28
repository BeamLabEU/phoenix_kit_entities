# Follow-up Items for PR #39

Reviewed against `main` on 2026-08-28. CLAUDE_REVIEW raised 1 finding.
Fixed in this batch.

## Fixed (Batch 1 — 2026-08-28)

- **NITPICK** `entity_data.ex`'s `sort_rows/2` comment named a test file
  (`list_by_entities_test.exs`) that doesn't exist — the actual coverage
  lives in `entity_data_batch_counts_test.exs`. Corrected the comment.

## Gate

`mix precommit` (compile --warnings-as-errors, deps.unlock --check-unused,
hex.audit, format --check-formatted, credo --strict, dialyzer, test.js)
passes clean. `mix test`: 1145/1153 pass; the 8 failures are
`SchemaOwnerGuardTest`/`...WiringTest` (from PR #38, unrelated to this
PR's changes) hitting a sandbox Postgres permission restriction — see
`../38-i067-schema-owner-guard/FOLLOW_UP.md`. Every test touching this
PR's own code (`entity_data_batch_counts_test.exs`, `form_builder_render_
test.exs`, `data_form_live_test.exs`, `data_navigator_live_test.exs`,
`entity_form_live_test.exs`, `test/js/slug_from_title.test.cjs`) passes.

## Open

None.
