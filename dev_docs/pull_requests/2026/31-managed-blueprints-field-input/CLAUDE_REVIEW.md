# PR #31 Review — Managed blueprints, FieldInput component, and real image/video field types

**Author:** Max Don (mdon)
**Reviewed:** 2026-08-19
**Verdict:** APPROVED — merged, with one fix on top

---

## Scope

Three features landed together: `PhoenixKitEntities.Managed` (write-path protection
for blueprints owned by another module, e.g. the catalogue's attribute sets),
`Components.FieldInput` (a control-only per-field renderer for hosts that own their
own layout) plus `FormBuilder.cast_field/2`, and real `image`/`video` field types
(storage-file-uuid references resolved through a media picker). The PR description
also claims a same-day quality-sweep pass (six triage agents) fixed two Managed-guard
bypasses, an atom-error spec widening, importer refusal labelling, `activity_log: false`
honoring, and i18n drift. All of those specific claims were checked against the merged
code, not taken on faith, and all hold up:

- `create_entity/2`, `update_entity/3`, `delete_entity/2` in `phoenix_kit_entities.ex`
  each route through `Managed.validate_creation/2`, `validate_mutation/3`,
  `validate_delete/2` — the guards are wired into the one write path every caller
  shares, not just theater in the admin LiveView.
- `acquires_markers?/3` (the create-then-update masquerade) is checked *before* the
  `not managed?(entity)` short-circuit, so an update that stamps `managed_by` onto a
  previously-unmanaged blueprint can't wave itself through by reading stale settings.
- `claimed_owner/1` checks both atom- and string-keyed `settings["managed_by"]` —
  Ecto's `:map` type round-trips atom keys as-given, and the JSONB encoder writes them
  out as strings, so a string-only lookup would fail open on an atom-keyed payload.
- `run_delete_guard/2` fails closed on both `rescue` and `catch :exit` — a stale local
  fun capture in `:persistent_term` after a code reload raises; a guard whose DB call
  exits (dead pool owner) exits, not raises. Both paths return
  `{:error, :delete_guard_error}` rather than crashing the caller.
- `FieldInput`'s media-ref render guard (`valid_media_ref?/1`), `FormBuilder.cast_field/2`
  → `validate_type/2`, and `EntityData.changeset/2`'s `validate_media_field/2` all
  independently `Ecto.UUID.cast/1` the value — a real type check at every layer, not a
  bare presence check, so a junk binary can't reach `URLSigner.signed_url/2` or storage.
- `en`/`et`/`ru` `default.po` all carry non-empty `msgstr` for every new msgid (`Image`,
  `Video`, both descriptions, `Change`/`Choose`/`Clear`, the managed-blueprint flash);
  `gettext_catalogue_test.exs`'s empty-msgstr and binding-parity tests are real and
  cover exactly this.
- `activity_log: false` is implemented and tested for `EntityData` lifecycle logging
  only (`entity_data.ex`, exercised by `LiveDataForm` autosave) — the PR description's
  "honored on all lifecycle events" reads as "all `EntityData` events", which is
  accurate; `Entities.create/update/delete_entity` never claimed the opt and don't need
  it (nothing autosaves a blueprint).
- `mirror/importer.ex` now pattern-matches `{:error, %Ecto.Changeset{}}` vs.
  `{:error, reason}` separately, so a `:managed_blueprint`/`:locked_key` atom refusal is
  labelled `{:refused, reason}` instead of being mislabeled `{:validation_failed, atom}`.
- `web/entity_form.ex` maps `{:error, reason} when reason in [:managed_blueprint,
  :locked_key]` to a real flash instead of falling into the `rescue` clause below and
  reading as an unexplained crash.

---

## Findings

### BUG - HIGH — managed blueprints reappear in the generic admin after a reorder or any entity-lifecycle broadcast *(fixed on main)*

`Managed`'s own moduledoc states guarantee #1 as "**Hidden from the generic admin**",
implemented by `include_managed: false` at every `Entities.list_entities/1` call site
that feeds the admin listing. The PR added that option to three of the five
`list_entities/1` calls in `lib/phoenix_kit_entities/web/entities.ex` — the initial
`handle_params/3` load and both the archive/restore success paths — but missed two:

- `handle_event("reorder_entities", ...)`'s success branch (re-fetches `:entities`
  after a successful drag-and-drop reorder).
- `handle_info({event, _uuid}, socket)` for `:entity_created`/`:entity_updated`/
  `:entity_deleted` — the PubSub-driven live-refresh handler. `Events.broadcast_entity_*`
  is unscoped (module-wide topic, not per-admin-session), so this fires for *any*
  entity mutation anywhere in the app, including the catalogue provisioning its own
  managed blueprints.

Net effect: open the Entities admin, then either drag-reorder any row or have any
other admin (or the owning module) touch any entity anywhere — the managed blueprint
that guarantee #1 promises to hide reappears in the list for as long as the LiveView
stays mounted. Classic two-call-sites-diverge regression — exactly the "list that must
stay in sync" pattern this codebase's own review history flags repeatedly, and it had
zero test coverage: `managed_test.exs` only asserts the underlying
`list_entities(include_managed: false)` function excludes managed rows, never that the
LiveView's post-action refresh calls it with that option.

**Fix:** added `include_managed: false` to both remaining call sites
(`lib/phoenix_kit_entities/web/entities.ex`, reorder success branch and the
`handle_info` live-update clause). Added two regression tests in
`test/phoenix_kit_entities/web/entities_live_test.exs`:
`"managed blueprints stay hidden from the list after a reorder refresh"` and
`"entity_updated refresh keeps managed blueprints hidden from the list"` — both create
a managed blueprint via `on_behalf_of: "catalogue"`, trigger the respective refresh
path, and assert the managed entity's display name never renders.

---

## Not changed

Everything else reviewed above (guard completeness, FieldInput firing discipline,
UUID validation at all three layers, i18n catalogue, importer/entity_form refusal
labelling) was independently verified against the merged code and found correct as
described in the PR body — no further changes made.
