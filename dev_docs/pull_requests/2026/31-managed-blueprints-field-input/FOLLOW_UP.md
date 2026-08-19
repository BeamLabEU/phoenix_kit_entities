# Follow-up Items for PR #31

Reviewed against `main` on 2026-08-19. CLAUDE_REVIEW raised 1 finding. Fixed in this batch.

## Fixed (Batch 1 — 2026-08-19)

- ~~**BUG - HIGH** managed blueprints reappear in the generic admin after a
  reorder or any entity-lifecycle broadcast~~ — `web/entities.ex` added
  `include_managed: false` to 3 of 5 `list_entities/1` call sites feeding the
  admin listing; missed the `reorder_entities` success branch and the
  `handle_info` PubSub live-refresh clause (`:entity_created`/`:updated`/
  `:deleted`), the latter reachable from *any* entity mutation anywhere in
  the app since `Events.broadcast_entity_*` is unscoped. Added
  `include_managed: false` to both remaining call sites. Pinned with two
  regression tests in `entities_live_test.exs` that create a managed
  blueprint via `on_behalf_of: "catalogue"` and assert it stays out of the
  render after a reorder and after a simulated `:entity_updated` broadcast.

## Also fixed while running the release gate (pre-existing, unrelated to #31)

- **`EntityData.bulk_delete/2` re-raised instead of returning
  `:referenced_by_external` for `ON DELETE RESTRICT` FKs.** `mix test` failed
  on `entity_data_trash_test.exs`'s existing `bulk_delete` FK-violation case.
  Root cause: `foreign_key_or_not_null_violation?/1` (added in `0cf10fc`,
  issue #12 — not part of #31) only matched SQLSTATE `23503`/`23502`, but an
  explicit `ON DELETE RESTRICT` constraint (as opposed to the default `NO
  ACTION`) raises `23001` (`restrict_violation`) instead. The single-record
  `delete/2` path was unaffected because `Repo.delete/1` goes through a
  changeset and Ecto normalizes both codes to `Ecto.ConstraintError{type:
  :foreign_key}`; `bulk_delete/2`'s raw `delete_all` bypasses that
  normalization and depends entirely on this helper. Added `23001` /
  `:restrict_violation` to the match in `entity_data.ex`. `mix test` is green
  (1101 tests, 0 failures) after the fix.

## Verified, no change needed

Every other claim in the PR description (Managed guard completeness and
call-site wiring, the acquisition-masquerade ordering, atom/string
`managed_by` key handling, the delete-guard fail-closed behavior on both
raise and exit, FieldInput's per-type firing discipline, `Ecto.UUID.cast/1`
validation at all three layers for image/video values, the i18n catalogue
and its empty-msgstr/binding-parity tests, `activity_log: false` scope, and
the importer/`entity_form` refusal-labelling fixes) was checked directly
against the merged code rather than taken from the description, and held up
as described. See CLAUDE_REVIEW.md for the specifics checked at each point.
