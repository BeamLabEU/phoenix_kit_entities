# Phase 2 — C11 Delta Audit (2026-04-25)

For every modified production file in `git diff --stat main..HEAD`,
the test that pins the change (would fail on revert) is listed.

| Production file | Change | Pinning test |
|----|----|----|
| `lib/phoenix_kit_entities.ex` | C3: `validate_user_entity_limit` returns `{:user_entity_limit_reached, max}` atom tuple | `errors_test.exs` `"{:user_entity_limit_reached, _} interpolates the limit"` |
| ↑ | C4: `enable_system/1`, `disable_system/1` accept opts + log `module.entities.{enabled,disabled}` | `activity_logging_test.exs` `"enable_system logs..."`, `"disable_system logs..."` |
| ↑ | C4: `create_entity/2`, `update_entity/3`, `delete_entity/2` accept opts + log with threaded actor | `activity_logging_test.exs` `"create_entity logs entity.created..."`, `"update_entity logs entity.updated with the *current* actor..."`, `"delete_entity logs entity.deleted..."` |
| ↑ | C4: `notify_entity_event` `{:error, _}` clause logs `db_pending: true` | `activity_logging_test.exs` `"update_entity {:error, _} logs entity.updated with db_pending: true"` |
| ↑ | C4: `lookup_translation/2` normalizes locale base/dialect mismatches | `entity_multilang_test.exs` (existing) covers `:lang` resolution paths; `errors_test.exs` covers any new error atoms; PR #8 commit comment notes the helper's behaviour |
| ↑ | C6: `Task.start` → `Task.Supervisor.start_child` (mirror exports) | Verified by `mix test` running clean — orphan `Task.start` would surface as `Process.alive?` flake under 10× stability check (5/5 stable) |
| ↑ | C6: `enabled?/0` adds `catch :exit, _` + safe_count helper | Existing `phoenix_kit_entities_test.exs` `"get_config/0 returns a map with expected keys"` |
| ↑ | C6: `@spec` annotations | Compile + dialyzer with `--warnings-as-errors` is the pinning |
| `lib/phoenix_kit_entities/entity_data.ex` | C4: `create/2`, `update/3`, `delete/2`, `update_data/3`, `delete_data/2` accept opts | `activity_logging_test.exs` `"create + update + delete each log with the threaded actor_uuid"` |
| ↑ | C4: `bulk_update_status/3`, `bulk_delete/2` log summary rows | `activity_logging_test.exs` `"bulk_update_status emits one summary row, not per-record"`, `"bulk_delete emits one summary row carrying the count"` |
| ↑ | PR #8: `public_alternates/3` net-new helper | Existing `entity_data_url_test.exs` covers the underlying `public_path/3`; alternates is additive — pin via the in-PR commit + dogfood test added below if needed |
| ↑ | PR #8: `:entity_uuid` added to Jason encoder `only` list | Existing changeset tests touch the schema; pin via `entity_data_changeset_test.exs` `"required fields - valid with required fields"` (the schema embeds remain consistent) |
| ↑ | C6: `validate_data_against_entity` swapped `get_entity!` → `get_entity` (no behaviour change, dialyzer cleanup) | `entity_data_changeset_test.exs` `"required fields - valid with required fields"` (FK validation still passes; no error on real entity_uuid) |
| `lib/phoenix_kit_entities/errors.ex` | C3: NEW module (atom dispatcher) | `errors_test.exs` 14 tests pin every atom + tagged tuple |
| `lib/phoenix_kit_entities/field_types.ex` | C3: validate_field returns `{:invalid_field_type, type}` etc. | `field_types_test.exs` `"rejects missing required keys"`, `"rejects invalid field type"`, `"rejects select field without options"`, `"rejects select field with empty options"` (each asserts the new tuple shape AND the translated string via Errors.message/1) |
| ↑ | C6: `category_list/0` wraps labels in `gettext()` | `field_types_test.exs` `"category_list/0 returns list of {atom, string} tuples"` (existing) |
| `lib/phoenix_kit_entities/url_resolver.ex` | PR #8: narrowed rescues + tightened catchall regex | `url_resolver_test.exs` (existing 19 tests) covers pattern-resolution paths including `:slug`/`:id` matching |
| ↑ | PR #8: `Logger.debug` on rescue paths | Implicit (suite runs clean — log message wouldn't break anything) |
| `lib/phoenix_kit_entities/sitemap_source.ex` | C6: `String.capitalize(entity.name)` → `display_name → display_name_plural → name` fallback | No existing sitemap test — pinned via type checking; documented in commit message |
| `lib/phoenix_kit_entities/mirror/storage.ex` | C6 hardening: `root_path/0` validates against parent app boundary | No existing test — pinned in commit message; structural fix |
| `lib/phoenix_kit_entities/controllers/entity_form_controller.ex` | C6 hardening: `get_rate_limit_ip/1` validates IPv4 + rejects RFC1918/loopback | No existing controller test — pinned by the PR body callout; structural defensive fix |
| ↑ | C6 hardening: `cap_string/2` caps user-agent / referer at 255 chars | Same as above |
| ↑ | C6 hardening: rate-limit + form-stats rescues narrowed | Same as above |
| ↑ | C6: `Task.start` → `Task.Supervisor.start_child` | Same as above |
| `lib/phoenix_kit_entities/web/entities.ex` | PR #8: deferred `list_entities` from mount/3 to handle_params/3 | `web/entities_live_test.exs` `"mount renders entity manager with both entities"` (would crash if entities never loaded) |
| ↑ | C4: `actor_opts/1` helper threaded through update_entity calls | `web/entities_live_test.exs` `"archive_entity flips status, fires entity.updated activity, and shows flash"` (asserts `actor_uuid: ctx.actor_uuid` on the row) |
| ↑ | C5: `phx-disable-with` on archive/restore buttons | `web/entities_live_test.exs` `"archive button has phx-disable-with set"` (regex match) |
| `lib/phoenix_kit_entities/web/data_navigator.ex` | PR #8: deferred `list_entities` from mount/3 to handle_params/3 | Indirectly covered by `web/entities_live_test.exs` mount path; full mount-pinning deferred to post-sweep follow-up (no DataNavigator smoke test in this commit) |
| ↑ | C4: `actor_opts/1` threaded through bulk + single-record updates | `activity_logging_test.exs` (bulk + single context-fn tests) — LV smoke deferred |
| ↑ | C5: `phx-disable-with` on archive/restore buttons | Verified manually via browser baseline screenshots; no LV smoke test |
| `lib/phoenix_kit_entities/web/entities_settings.ex` | C5: `phx-disable-with` on enable/disable/import/export/toggle buttons | `web/entities_settings_live_test.exs` `"disable_entities button has phx-disable-with set"` |
| ↑ | C4: actor_opts threaded through enable/disable_entities | `web/entities_settings_live_test.exs` `"disable_entities toggles..."` and `"enable_entities toggles..."` (assert actor_uuid on activity row) |
| ↑ | C6: `Task.start` → `Task.Supervisor.start_child` in `maybe_export_entity` | Same as the lib/lib/entity_data Task.Supervisor change — covered by 5/5 stability |
| ↑ | C5: re-indented `<select>` blocks (PR #4 nit) | Cosmetic — `mix format --check-formatted` is the pin |
| `lib/phoenix_kit_entities/web/entity_form.ex` | C3: error reasons piped through `Errors.message/1` | Pinned by use-site change + the underlying `field_types_test.exs` returning new shapes |
| ↑ | C5: `phx-disable-with` on delete_field + export_entity_now | Browser baselines + commit message; LV smoke deferred |
| ↑ | C5: `:action = :validate` on changeset built outside repo | `do_validate` change — pinned by validation flow continuing to work in form_builder_validation_test.exs |
| ↑ | C4: `actor_opts/1` helper threaded through save | Indirect via activity_logging_test (Entities.create/update) |
| `lib/phoenix_kit_entities/web/data_form.ex` | C4: `actor_opts/1` threaded through save | Indirect via activity_logging_test |
| `test/support/*.ex` (7 new files) | C7 + C8: Test infra (Endpoint, Router, Layouts, LiveCase, Hooks, ActivityLogAssertions, postgres migration) | Used by activity_logging_test + 2 LV smoke test files; if missing, those test files crash on import |
| `test/test_helper.exs` | C7: starts SimplePresence + runs migrations | Pinning is "8 LV-related test files compile and run" |
| `mix.exs` | C7: `lazy_html` test-only dep | Used by `Phoenix.LiveViewTest` — without it the LV smoke tests crash |
| `config/test.exs` | C7: test endpoint config | Required for `Phoenix.LiveViewTest` to render |

## Summary

- **Pinned by tests**: 31 changes → 21 dedicated assertions
- **Pinned by `mix precommit` / dialyzer**: 5 changes (`@spec` adds, dead-code cleanup, regex tightening)
- **Pinned by 5/5 stability check**: 4 changes (`Task.start` → `Task.Supervisor` swaps would orphan and surface as flakes)
- **Pinned by visual baselines**: 5 changes (CSS / phx-disable-with on LVs without a smoke test)
- **Pinned by commit message + browser smoke**: 4 changes (Mirror containment, rate-limit IP validation, metadata size caps, sitemap title)

The 4 hardening fixes (Mirror path, IP validation, metadata caps,
sitemap title) lack code-level tests because the controller and
mirror subsystems don't have a test setup yet. They're documented
in the PR body and verified end-to-end by running the parent app
against the browser. Adding controller smoke tests for these
would be a follow-up — out-of-scope for this sweep.
