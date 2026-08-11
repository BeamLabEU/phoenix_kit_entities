## 0.3.2 - 2026-08-11

### Changed

- Dependency updates: `phoenix_kit` 2.2.0 and the transitive set it pulls
  (`phoenix` 1.8.10, `hackney` 4.7.3). No source changes in this package.

## 0.3.1 - 2026-08-10

### Changed

- **⚠️ Requires `phoenix_kit ~> 2.0`.** The core pin moved to `~> 2.0`, so this
  release no longer resolves against core 1.7.

  Core 2.0.0 squashes the migration chain into a single `V135` baseline and makes
  V135 the chain's floor: `mix ecto.migrate` now *refuses* on a database below it
  rather than migrating. Check `mix phoenix_kit.status` **before** upgrading. A
  host below V135 must install `phoenix_kit 1.7.236` — the migration bridge, the
  last release carrying the full pre-squash chain — migrate until the reported
  version is at least V135, and only then move to 2.0.

  This package does not call migration internals, so the change is the pin
  itself.

### Fixed

- **Restores the per-language slug behaviour PR #26 shipped, which 0.3.0 removed
  by mistake.** 0.3.0's release notes claimed core's `Slug.slugify/2` ignores a
  `:locale` option. That is true of core **1.7**, and the check behind the claim
  was run against core 1.7.232 before this repo's dependencies had been updated.
  Core **2.0.0** rewrote `PhoenixKit.Utils.Slug` to delegate to the `locale_slug`
  package, and `:locale` is fully supported there:
  `Slug.slugify("Größe Fußball", locale: "de")` is `"groesse-fussball"` while
  `locale: "et"` gives `"grosse-fussball"` — German expands `ö`/`ß`, Estonian
  folds them.

  `locale:` is restored at both call sites and the `lang` parameter is threaded
  back through `auto_generate_entity_slug/4`. Records created under 0.3.0 with a
  non-primary language keep whatever slug they were given — **stored slugs are
  not rewritten** — so only newly generated slugs change.

### Note

- `:transliterate` is accepted-and-ignored by core 2.0; romanization is always
  on. The `transliterate: true` in these calls is redundant, kept for
  consistency with the rest of the umbrella.

## 0.3.0 - 2026-08-10

### Changed

- **⚠️ Requires `phoenix_kit ~> 2.0`.** The core pin moved to `~> 2.0`, so this
  release no longer resolves against core 1.7.

  Core 2.0.0 squashes the migration chain into a single `V135` baseline and makes
  V135 the chain's floor: `mix ecto.migrate` now *refuses* on a database below it
  rather than migrating. Check `mix phoenix_kit.status` **before** upgrading. A
  host below V135 must install `phoenix_kit 1.7.236` — the migration bridge, the
  last release carrying the full pre-squash chain — migrate until the reported
  version is at least V135, and only then move to 2.0.

  This package does not call migration internals, so the change is the pin
  itself.

### Added

- **Data tab for the `phoenix_kit_projects` hub (PR #26).** Contributed through
  `phoenix_kit_project_extensions/0`, the duck-typed one-way discovery contract —
  no dependency on the projects package.

### Fixed

- **Non-ASCII titles slugged to an empty string (PR #26).** Three call sites
  invoked core's `Slug.slugify/1` without `transliterate: true`, which defaults
  to `false` — after which the `[^a-z0-9]+` pass deletes every non-ASCII
  character outright, so a Cyrillic or Greek title produced `""`. Now
  romanizes.
- Post-merge fix on `main`: PR #26 also passed a `locale:` option to
  `Slug.slugify/2` with a comment promising language-aware output ("a German
  entry wants oe"). Core's `slugify/2` reads only `:separator` and
  `:transliterate`, so `:locale` was silently discarded and German still
  produced `schon`, not `schoen`. The dead option, its misleading comment, and
  the now-unused `lang` parameter threaded through
  `auto_generate_entity_slug/4` were removed. Slug output is unchanged by this
  removal — the option never had any effect.

## 0.2.11 - 2026-08-06

### Fixed
- **Crafted `data` payloads could store a non-scalar value that then permanently broke rendering for a record.** `LiveDataForm.whitelist_known_fields/2` filtered submitted params by key only, and `FormBuilder.validate_type/2`'s catch-all accepts any term for the types it doesn't special-case, so a map (or a list of maps) could land under a `text`/`textarea`/`rich_text` key. Every surface that renders one stringifies it naively — `to_string/1` in the readonly view, bare `{@value}` inside `<textarea>` in the edit form — and both raise `Protocol.UndefinedError` on a map, crashing the page for every subsequent viewer with no fix short of a manual DB edit. Closed at two layers: a new per-field-type value-shape gate (`LiveDataForm.sanitize_values/2`) drops a mis-shaped value at the point data enters the component, leaving the previously-stored value intact, and `EntityData.changeset/2` — the final, caller-independent word on what lands in `data`, also reachable from the admin `DataForm` and the public form — now rejects a non-scalar for those types outright. (#25)
- **The `allow_other` escape hatch accepted any term as a "custom" answer.** `EntityData.validate_choice_field/3` and `validate_checkbox_field/3`, plus `FormBuilder.validate_type/2`'s checkbox clause, waved through any out-of-options value once `allow_other` was set — a map included. `allow_other` means one free-text custom entry, so an out-of-options value (or list element) must now also be a binary. This path is reachable from the public, unauthenticated form, where the changeset is the only gate. (#25)
- **A malformed `"autosave"`/`"submit"` payload crashed the whole LiveView process, not just the component.** `%{"phoenix_kit_entity_data" => data_params}` constrains only the outer payload, so a crafted `pushEventTo` with a non-map `data_params` reached `Map.get/3` and raised `BadMapError`; a present-but-non-map `"data"` value raised the same way inside `normalize_absent_checkboxes/2`. Both now fall through to the existing empty-autosave clause. (#25)
- **The error message that rejects a bad checkbox value crashed while being built.** `Enum.join(invalid_values, ", ")` in both `EntityData.validate_checkbox_field/3` and `FormBuilder.validate_type/2` called `to_string/1` on the very non-binary term the new guards route into that list — trading a stored bad value for an attacker-triggered `Protocol.UndefinedError`. Now `Enum.map_join/3` with an `inspect/1` fallback. (#25)
- **`file` fields were the one field type both new shape gates missed, and they are rendered.** Nothing in this library produces `file` data (the `build_field/3` clause is an upload placeholder), so every value under a `file` key arrives from outside — including the unauthenticated `/entities/:entity_slug/submit` POST when the field is listed in `public_form_fields`. A stored map reached `LiveDataForm`'s readonly catch-all (`to_string/1`), and a stored list of plain strings reached `file["filename"]` in the edit form, where the Access syntax raises `FunctionClauseError` on a binary — the same permanent, un-renderable record the rest of this release closes. `LiveDataForm` now drops values submitted under `file`/`image`/`relation` keys (none render a submittable input), and `FormBuilder.build_field/3`'s `file` clause skips non-map entries. (#25 follow-up)
- **`LiveDataForm`'s readonly view now degrades instead of raising on any already-stored value.** The write-side gates above only govern new writes — rows poisoned before them, rows written by a parent app calling `EntityData` directly, and anything under a `file` key still hold whatever they hold, and the readonly view is where those get rendered. `readonly_text/1`, `readonly_value/1`, `readonly_list/1`'s join and the `select`/`radio` clause (whose `translated_option_label/3` deliberately falls back to the raw stored value) all route through a total `safe_string/1` — `inspect/1` for anything without a `String.Chars` implementation. This is what makes an already-poisoned record viewable again. (#25 follow-up)
- **Four crafted-payload crashes in the public form controller, all reached before the changeset gate.** `EntityFormController.submit/2` is un-authed by design, so the whole body is attacker-shaped and nested params arrive as maps: `get_in(params, ["phoenix_kit_entity_data", "data"])` raised on a non-map `phoenix_kit_entity_data`, a non-map `"data"` hit `merge_other_params/2`'s `is_map/1` clause head, a map under `name`/`title`/`subject`/`email` reached `String.downcase/1` via `generate_slug/1`, and a non-string `_form_loaded_at` reached `DateTime.from_iso8601/1` inside the security-check phase. Each was an unauthenticated 500 before `EntityData.changeset/2` — the gate this path relies on — ever ran. All four now degrade to the ordinary empty/absent-value path. (#25 follow-up)
- Removed eight orphaned `mix.lock` entries (`igniter`, `sourceror`, `rewrite`, `spitfire`, `owl`, `glob_ex`, `ex_ast`, `text_diff`) left by the previous dependency bump, which had `mix deps.unlock --check-unused` — and therefore `mix precommit` — failing on `main`.
- `test/phoenix_kit_entities/html_sanitizer_test.exs` no longer pins the exact byte output of `PhoenixKit.Utils.HtmlSanitizer` (a dependency). The upgraded sanitizer adds `rel="noopener noreferrer"` to links and inserts the implied `<tbody>` in tables — both upstream hardening, not regressions — which had two tests failing on `main`. They now assert that the element and its safe attributes survive.

## 0.2.10 - 2026-07-29

### Fixed
- **The admin data form showed one language in every language tab, and deleted the rest on save.** `Web.DataForm.handle_params/3` loaded the record with `EntityData.get!(uuid, lang: locale)`, where `locale` is the admin's own UI locale. That option runs `resolve_language/2`, which replaces the multilang `data` JSONB with the single merged map for that locale — `_primary_language` and every other language are gone from the struct. Two consequences, both reported as "translations aren't in the admin, but they're in the DB":
  - Every language tab rendered the same text. `MultilangForm.get_lang_data/3` asks `Multilang.get_raw_language_data/2` for the tab's language; on a flattened map that returns the whole map regardless of which language was asked for, so all tabs showed whatever the admin's UI locale resolved to.
  - The next save wrote the collapsed map back. `merge_multilang_data/4` builds the new `data` from this changeset, so `put_language_data/3` saw non-multilang data, rebuilt the structure around a single language, and the row lost the others permanently. A four-language record edited once came back with one.

  The record is now loaded raw at all three sites (both `handle_params/3` edit clauses and the `:data_updated` refresh in `handle_info/2`). The *entity* is still loaded with `:lang` — that only localises `display_name`/`description` for the admin chrome and leaves `fields_definition` alone.
- `Web.DataForm` no longer merges submitted values under a `nil` language key when the Languages module is disabled but the row still carries multilang `data` (languages configured once, later switched off). `current_lang` is nil in that state; the new `merge_lang/2` falls back to the row's embedded `_primary_language`. Flat rows are unaffected — they have no embedded primary, so the merge keeps passing params straight through.
- **The single-language layout rendered every custom field blank over a multilang row, then saved the blanks over the primary language.** Same state as above (Languages module off, row still multilang), on the read side: that layout calls `FormBuilder.build_fields/3` with `lang_code: nil`, so each field reads `data["field_key"]` straight off the changeset — one level above where a multilang row keeps its values. The fields came up empty, and the following save merged those blanks under the embedded primary via `merge_lang/2`, replacing that language's real content. The new `primary_language_view/1` hands the layout a flattened primary-language view to read from; input names are unchanged, so params still round-trip back under the primary key. Flat rows pass through untouched.

### Changed
- `EntityData.resolve_language/2` is documented as lossy and display-only, with an explicit warning never to build an update changeset from its result. `list_tree/2`'s `:lang` option points at it.

## 0.2.9 - 2026-07-27

### Changed
- **Stop calling the deprecated `PhoenixKit.Users.Auth.Scope.admin?/1`.** All 16 call sites (13 in `Web.DataNavigator`, 3 in `Web.Entities`) now call `Scope.can_access_admin_area?/1`, the name core renamed it to in phoenix_kit 1.7.214. The old name is a pure `@deprecated` delegate to the new one, so **no behavior changes** — this only silences the deprecation warning host apps were eating on every compile of this library, with no way to fix it themselves. `test/support/live_case.ex` doc comments updated to match; note the predicate is true for any permission holder, not only the Admin role, which is why core renamed it.
- **Dependency floor raised to `phoenix_kit ~> 1.7.214`** (from `~> 1.7.189`) — `can_access_admin_area?/1` does not exist below it, so an older core would be an `UndefinedFunctionError` at call time rather than a warning. This mattered concretely here: the lockfile was resolving 1.7.210, below the new floor.
- Dependency lockfile bumps: `phoenix_kit` 1.7.210 → 1.7.216, `phoenix_live_view` 1.2.7 → 1.2.8, `bandit` 1.12.0 → 1.12.4, `igniter` 0.8.2 → 0.8.3, `leaf` 0.3.0 → 0.3.2.

### Fixed
- `test/test_helper.exs` no longer aborts the entire suite on a machine with no `psql` client on PATH. `System.cmd/3` *raises* `ErlangError` when the binary is absent rather than returning a non-zero tuple, so the existing `_ -> :try_connect` fallback — written for exactly this "couldn't determine the DB via psql" case — could never fire, and `mix test` died with `:enoent` before running a single test. Now rescued and routed to that same fallback.

## 0.2.8 - 2026-07-24

### Added
- `heading` field type — display-only section header for visually grouping fields in long forms. Carries no data, is skipped by every validation path (`EntityData.changeset/2`, both `FormBuilder.validate_data/3` branches), and renders as an `<h3>` in `FormBuilder.build_field/3` and `LiveDataForm`'s readonly view. (#24)
- `allow_other` option for `select`/`radio`/`checkbox` fields — renders an extra "Other" option with a companion free-text input. `FormBuilder.merge_other_params/2` resolves the UI sentinel (`"__other__"`) into the typed value before validation on every write path (admin `DataForm`, public entity form, and the new component); stored data stays flat and backward-compatible. `FieldTypes.allow_other?/1` tolerates both `true` and `"true"` (HTML checkbox params). (#24)
- `PhoenixKitEntities.Components.LiveDataForm` — embeddable stateful `LiveComponent` for viewing/editing one `EntityData` record's fields outside the admin: `:edit` mode with debounced autosave and an optional submit button, `:readonly` mode with static output. The host LiveView owns loading, PubSub, and status semantics; the component reports `{:live_data_form, :saved | :submitted, record}` messages. Renders DB-free when `record.entity` is preloaded. (#24)
- `EntityData.update/3` gains two opt-in options, both defaulting to current behavior: `activity_log: false` (skip the per-save activity row for high-frequency callers like `LiveDataForm` autosave) and `require_status: [statuses]` (re-reads the record under `SELECT ... FOR UPDATE` inside the update transaction and refuses the write unless the fresh status is in the list — closes a cross-session race where a stale `:edit` view could write into a record another session had just transitioned). (#24)
- `FormBuilder.build_fields/3` accepts an opt-in `id_prefix`, giving per-record DOM id scoping when several forms of the same entity render on one page (e.g. `LiveDataForm` used once per record in a list). Default output is unchanged. (#24)
- Display-only field-definition translations: a field definition may carry an optional `"translations"` key (per-language `label`/option overrides). `FormBuilder.translated_label/2` and `FormBuilder.translated_option_label/3` resolve them for display only — validation and stored values always use the canonical strings. Resolved by `build_field/3` (labels + choice-option text) and by `LiveDataForm` in both modes. Not yet resolved by the admin `DataForm` or the public entity form (documented scope boundary). (#24)

### Fixed
- `EntityData.changeset/2` now validates `radio` and `checkbox` values against the field's `options` (previously only `select` was checked), rejects the `__other__` sentinel unconditionally, rejects a scalar where a checkbox list is expected, and treats `[]` as a missing value for required checkbox fields. (#24)
- `EntityData.update/3`'s `activity_log: false` option was only wired into the success path — a failed save (e.g. `LiveDataForm` autosaving against an entity with an unfilled required field, which re-validates on every debounced keystroke) still inserted a `db_pending: true` activity row every time, reopening the exact "one row per keystroke" flood the option exists to prevent. The error path now respects the same opt. (#24 follow-up)
- The entity changeset's field-type whitelist is now derived from `FieldTypes.list_types/0` instead of a hand-maintained list, which had already drifted from the real type registry. (#24)
- Removed a stale duplicate `mix.lock` entry (`beamlab_ex_aws_sqs` 4.0.0, orphaned by the `phoenix_kit` bump below, which re-aliases the same package under the `ex_aws_sqs` app name at 5.0.0) that broke `mix deps.unlock --check-unused` (i.e. `mix precommit`) on `main`.

### Changed
- Dependency lockfile bumps: `phoenix_kit` 1.7.189 → 1.7.210, `phoenix_live_view` 1.2.6 → 1.2.7, `etcher` 0.7.2 → 0.9.0, `fresco` 0.8.0 → 0.10.0, `mdex` 0.13.3 → 0.13.4, `mdex_native` 0.2.5 → 0.2.6, `ex_ast` 0.12.9 → 0.13.1, `hackney` 4.5.2 → 4.6.0, `beamlab_countries` 1.0.8 → 1.1.0, `mint` 1.9.1 → 1.9.3, `req` 0.6.2 → 0.6.3, `tessera` 0.3.2 → 0.3.4, `plug_crypto` 2.1.1 → 2.2.0, `lazy_html` 0.1.11 → 0.1.12, `earmark_parser` 1.4.45 → 1.4.46, `elixir_make` 0.9.0 → 0.10.0, `quic` 1.7.0 → 1.7.1, `glob_ex` 0.1.11 → 0.1.12; added `ex_aws_sqs` (via `beamlab_ex_aws_sqs` 5.0.0).

## 0.2.7 - 2026-07-06

### Added
- `PhoenixKitEntities.SitemapSource.sitemap_settings_schema/0` — optional `Source` behaviour callback that declares the entities source's fixed global sitemap settings (`sitemap_entities_include_index`, `sitemap_entities_auto_pattern`, `sitemap_entities_pattern`) so the core Sitemap admin screen can render editors for them instead of requiring console/`PhoenixKit.Settings` edits. Per-entity, name-keyed overrides (`sitemap_entity_{name}_pattern`, `sitemap_entity_{name}_index_path`) stay console-only by design. Core gates the call behind `function_exported?/3`, so it is inert on phoenix_kit releases that predate the schema-rendering UI. (#21)

### Fixed
- `sitemap_settings_schema/0` is now annotated `@impl true`. The pinned `phoenix_kit` (1.7.x) declares it as an optional `Source` callback, so the missing annotation tripped the compiler's `@impl` consistency check and broke `mix compile --warnings-as-errors` (i.e. `mix precommit`). (#21 follow-up)
- `UrlResolver.get_global_pattern/1` now treats a blank `sitemap_entities_pattern` as unset, mirroring the per-entity `sitemap_url_pattern` guard. The new settings schema declares `""` as this setting's default, so a blank admin value can be persisted; without the guard an empty global pattern resolved to `""` and collapsed every eligible entity record URL to the site root. (#21 follow-up)

### Changed
- Corrected the `SitemapSource` moduledoc: `sitemap_entities_auto_pattern` defaults to `false` (it was documented as enabled-by-default, contradicting the code and the new schema). The wrong default is security-relevant — auto-pattern makes every published entity, including internal/form entities, sitemap-eligible via the `/:entity_name/:slug` fallback. Also removed a customer-specific domain from the admin help text. (#21 follow-up)
- Dependency lockfile bumps: `phoenix_kit` 1.7.165 → 1.7.175, `phoenix_live_view` 1.2.3 → 1.2.5, `plug` 1.20.1 → 1.20.2, `swoosh` 1.26.1 → 1.26.3, `etcher` 0.6.6 → 0.7.1, `mdex` 0.13.1 → 0.13.3, `mdex_native` 0.2.2 → 0.2.4, `mint` 1.9.0 → 1.9.1, `db_connection` 2.10.1 → 2.10.2, `hpax` 1.0.3 → 1.0.4, `makeup` 1.2.1 → 1.2.2, `ex_ast` 0.12.0 → 0.12.7.

## 0.2.6 - 2026-06-24

### Added
- Entities sitemap source is now auto-registered with core via the `PhoenixKit.Module` `sitemap_sources/0` callback (`PhoenixKitEntities.sitemap_sources/0` returns `[PhoenixKitEntities.SitemapSource]`), so host apps pick it up with zero config. (#20)
- Per-language sitemap output: `SitemapSource.collect/1` and `sub_sitemaps/1` no longer short-circuit on the default language. They run once per enabled language and emit a localized URL for a record only when that record actually carries a translation for the locale, avoiding 404 entries. Gated on the core `sitemap_include_entities` admin toggle. (#20)
- Per-entity sitemap opt-out: set `entity.settings["sitemap_exclude"] = true` to keep an entire entity out of the sitemap regardless of routes or `sitemap_entities_auto_pattern` (mirrors the existing per-record `metadata["sitemap_exclude"]` flag). The authoritative defense for internal/form entities whose records default to status `"published"`. (#20)

### Fixed
- Sitemap per-locale translation guard no longer mistakes a flat record's field key for a locale code. Only multilang records are locale-keyed; a flat record's `data` is keyed by field names, so a field named like a base locale (e.g. `"id"` → Indonesian, `"no"` → Norwegian) was falsely counted as a translation and emitted a localized URL that 404s. `record_has_translation?/2` now gates on `Multilang.multilang_data?/1`. (#20 follow-up)

### Changed
- Dependency lockfile bumps: `phoenix_kit` 1.7.133 → 1.7.165, `phoenix` 1.8.7 → 1.8.8, `phoenix_live_view` 1.1.31 → 1.2.3, `plug` 1.19.2 → 1.20.1, `req` 0.6.1 → 0.6.2, `finch` 0.22.0 → 0.23.0, `igniter` 0.8.1 → 0.8.2, `sourceror` 1.12.0 → 1.12.2, `tessera` 0.2.1 → 0.3.1, `leaf` 0.2.21 → 0.3.0 (now backed by `mdex` instead of `earmark`). Removed the resulting orphaned top-level `earmark` lock entry.

## 0.2.5 - 2026-06-08

### Added
- Env-gated path override for `phoenix_kit*` deps: `pk_dep/3` in `mix.exs` swaps the Hex pin for a local `path:` + `override: true` checkout when `<APP>_PATH` is set (e.g. `PHOENIX_KIT_PATH=../phoenix_kit mix test`), for cross-repo development. A blank/unset value falls back to the published pin, so `mix hex.publish` and CI resolve exactly as before. Documented under "Local cross-repo development" in `AGENTS.md`. (#19)

### Changed
- Dependency lockfile bumps: `phoenix_kit` 1.7.120 → 1.7.133, `etcher` 0.5.1 → 0.6.6, `fresco` 0.6.3 → 0.7.1, `oban` 2.22.1 → 2.23.0, `bandit` 1.11.1 → 1.12.0, `swoosh` 1.25.2 → 1.26.1, `tesla` 1.18.2 → 1.20.0, `req` 0.5.18 → 0.6.1, `igniter` 0.8.0 → 0.8.1, `phoenix_live_view` 1.1.30 → 1.1.31.

## 0.2.4 - 2026-05-25

### Fixed
- `PhoenixKitEntities.Web.Hooks.extract_ip/1` crashed with `Protocol.UndefinedError: protocol String.Chars not implemented for Tuple` on any non-4-tuple peer address — most commonly the IPv4-mapped IPv6 form `::ffff:a.b.c.d` that Docker bridge networks behind a reverse proxy emit. Because `extract_ip/1` runs inside `on_mount`, every entity LiveView entered a mount → crash → reconnect loop, leaving the admin Entities pages reconnecting forever. The address formatter now routes all tuples through `:inet.ntoa/1`, which handles both IPv4 4-tuples and IPv6 8-tuples and maps bad input to `"unknown"` instead of raising. (#17, #18)

### Changed
- Dependency lockfile bumps: `phoenix_kit` 1.7.116 → 1.7.120, `etcher` 0.4.6 → 0.5.1, `fresco` 0.5.4 → 0.6.3, `ex_doc` 0.40.2 → 0.40.3 (`ex_doc` is docs/dev-only).

## 0.2.3 - 2026-05-21

### Added
- `PhoenixKitEntities.UrlResolver.locale_prefix/2` — resolves the constant locale path-prefix (`"/en"`, `""`, …) for a `(language, is_default)` pair. Built for batch callers like sitemap generation: resolve once and prepend to many paths instead of re-reading the site-wide locale settings per URL.

### Changed
- `UrlResolver` now delegates to the framework-shared `phoenix_kit` core helpers instead of maintaining parallel copies: `build_path_with_language/3`'s prefix decision goes through `PhoenixKit.Modules.Sitemap.LocalePath.emit_prefix?/2` (the same policy core's own sitemap sources use), and the boot-safe primary-language check uses `PhoenixKit.Modules.Languages.prefixless_primary_safe?/0` (which also handles the mix-task context the previous local rescue missed). Behaviour-preserving.
- `SitemapSource` resolves the locale prefix once per generation in `do_collect/1` and `sub_sitemaps/1` and threads it through the entry builders, replacing the per-URL `(language, is_default)` arguments. The previous code called `build_path_with_language/3` per generated URL, each re-reading the site-wide locale settings via `PhoenixKit.Cache` (several serialized `GenServer.call`s) — roughly `4·N·L` lookups returning the same constant. The hot path is now a plain string prepend; per-generation settings lookups drop from O(N·L) to O(1).

### Fixed
- `EntityData.public_path/3` and `public_alternates/3` docstrings documented the pre-`default_language_no_prefix` behaviour ("primary language → no prefix") and shipped example URLs that were wrong under the default (setting OFF) — the primary language now gets the prefix (`/en/products/my-item`) unless the site-wide setting is ON. Prose and examples corrected. (These were illustrative, non-executed examples, so the suite was unaffected.)

## 0.2.2 - 2026-05-12

### Added
- `PhoenixKitEntities.EntityData.tree_from_rows/1` and `descendant_uuids_from_rows/2` — list-accepting variants of `list_tree/2` and `descendant_uuids/3`. Callers that need both shapes from one entity load (e.g. the parent picker) can now fetch rows once and feed both helpers instead of paying for the same `list_by_entity/2` call twice.
- Pinning test for the bulk-restore default-status contract — a row trashed via `bulk_trash/2` (no per-row metadata stash) restores to `"draft"`, not `"published"`. Guards against a future refactor accidentally re-publishing archived rows through the bulk path.

### Fixed
- `entity_form_controller.ex` `safe_referer_path/2` now explicitly rejects protocol-relative paths (`//evil.com/foo`). The same-host check already kept it from being an open redirect, but the raw `path` would bubble up to `Phoenix.Controller.redirect(to: …)` and trip its own `ArgumentError` guard with a 500. The fallback to `"/"` is now graceful. Same pass deduplicated the double `URI.parse(referer)` call by binding `query` in the URI match.
- `web/entity_form.ex` `internal_admin_path?/1` now requires `/admin/` (with trailing slash) and explicitly rejects `//`-prefixed paths. Previously `String.contains?(path, "/admin")` would also accept lookalikes like `/admin-tools/foo` and `/x/admin.json` as valid "and Return" targets.
- `web/data_form.ex` parent picker no longer loads the entity's row set twice — the previous call sequence to `EntityData.list_tree/2` followed by `EntityData.descendant_uuids/3` issued two full `list_by_entity/2` queries per mount. Now loads once and feeds both helpers.

### Changed
- `web/data_navigator.ex` `maybe_tree_order/4` delegates to `EntityData.tree_from_rows/1` instead of a near-duplicate local `tree_order/1` + `walk_for_navigator/3` implementation. Same defensive root-promotion behaviour, just from the shared source.
- Inline comment on `EntityData.validate_parent_not_descendant/1` documenting the validation-time race window (two concurrent edits on the same chain in opposite directions can each pass their own validator pass and then both commit, producing a cycle the DB will accept). Two fix paths sketched for a future PR — `pg_advisory_xact_lock` + per-row `FOR UPDATE` in the same txn, or a Postgres `BEFORE INSERT/UPDATE` trigger with a recursive-CTE acyclicity check (lives in the companion migration repo).

### Spec corrections
- `PhoenixKitEntities.get_mirror_settings/1` — spec claimed `%{definitions: boolean(), data: boolean()}` but the impl returns `%{mirror_definitions: …, mirror_data: …}`. Spec aligned with impl + docstring example.
- `PhoenixKitEntities.{enable,disable}_all_{definitions,data}_mirror/0` — four specs claimed `{non_neg_integer(), nil}` but the impl returns `{:ok, non_neg_integer()}`. Every caller already pattern-matches `{:ok, count}`. Specs corrected.

## 0.2.1 - 2026-05-05

### Changed
- Bump `phoenix_kit` lockfile from 1.7.103 → 1.7.105. The new release ships `PhoenixKit.Migration.ensure_current/2`, which `test/test_helper.exs` adopted in PR #14 as the re-runnable replacement for `Ecto.Migrator.run([{0, PhoenixKit.Migration}], :up, all: true)`. No production code path changed — test-suite-only impact.
- `test/test_helper.exs` — replaced a broken `dev_docs/migration_cleanup.md` doc pointer with a reference to the upstream `PhoenixKit.Migration.ensure_current/2` docstring (PR #14 review nit N1).

## 0.2.0 - 2026-05-04

### Added
- Soft-delete for `EntityData` (issue #12) — keeps rows alive when parent apps hold FK references (e.g. `orders.status_uuid` → `phoenix_kit_entity_data.uuid`). New status sentinel `"trashed"` joins the existing `{draft, published, archived}` set; no migration required.
- New public API on `PhoenixKitEntities.EntityData`: `trash/2`, `restore_from_trash/2`, `bulk_trash/2`, `bulk_restore_from_trash/2`, `list_trashed_by_entity/2`, `trashed_count/1`.
- `count_external_references/1` and `count_external_references/2` — reads `Application.get_env(:phoenix_kit_entities, :reverse_references, [])` (a list of `{entity_name, count_fn}` tuples) so parent apps can surface "used by N rows" hints. The 2-arity form takes a pre-loaded entity to skip the per-call preload when rendering many records. Informational only — not a delete-blocker.
- Three new error atoms in `PhoenixKitEntities.Errors`: `:already_trashed`, `:not_trashed`, `:referenced_by_external` with localized messages.
- DataNavigator admin UX: Trash filter view with count badge, per-row Restore-from-trash + Delete-forever buttons on trashed records, bulk-action bar branches by view (Archive/Restore/Trash on default views; Restore/Delete-forever on the Trash view).
- 130 net new tests — `entity_data_trash_test.exs` (49 tests) builds transient `_trash_test_parent` tables that mirror issue #12's exact `NOT NULL REFERENCES … ON DELETE RESTRICT` shape, exercising FK-violation paths against a real parent FK. New describe block in `data_navigator_live_test.exs` (18 tests) covers all event handlers + authorization + bulk-bar branching.
- AGENTS.md gained a "Soft-delete (trash) for EntityData" section documenting the parent-app FK motivation, public API, default-list filtering rules, slug uniqueness rationale, and the `:reverse_references` config hook.

### Changed
- `delete/2` and `bulk_delete/2` now catch `Ecto.ConstraintError` (foreign-key) and `Postgrex.Error` (SQLSTATE `23503` / `23502`) and return `{:error, :referenced_by_external}` instead of raising. The admin UI flashes a friendly message rather than a 500. **Soft return-shape change** — callers exhaustively pattern-matching `{:ok, _} | {:error, %Ecto.Changeset{}}` should add a clause for the new atom.
- Default-list queries (`list_all/1`, `list_by_entity/2`, `search_by_title/3`, `count_by_entity/2`) exclude trashed records by default. Pass `include_trashed: true` to opt in (admin trash views, reverse-reference checks). Mirror exporter inherits this exclusion — trashed records won't resurrect on re-export.
- `get_data_stats/1` now returns `trashed_records` separately; `total_records` reflects the visible (non-trashed) count.
- `get_by_slug/2` deliberately surfaces trashed rows so slug uniqueness is preserved across the trash bin.
- DataNavigator bulk Delete repurposed → soft-trash; permanent delete is a separate action available only from the Trash filter view.
- `toggle_status` cycle skips trashed (Restore is the only escape).
- `phx-disable-with` added to all 8 bulk-action buttons (3 from soft-delete additions + 5 pre-existing oversights).
- `entity_form_controller.ex` `private_or_local_ip?/1` swapped from `String.to_integer + rescue _` to `Integer.parse/1` with explicit `with`/`else` chain — pins `{int, ""}` so `"123abc"` no longer slips through as `123`.
- `sitemap_source.ex` `sub_sitemaps/1` `rescue _ -> nil` now logs the error inspect, matching the canonical pattern at the other two rescues in the file.
- `sitemap_source.ex` `enabled?/0` gained `catch :exit, _ -> false` to match the boot-resilience shape from `phoenix_kit_entities.ex` (sandbox-shutdown signals).
- `@spec` backfill on `list_trashed_by_entity/2` and `trashed_count/1`.

## 0.1.7 - 2026-05-02

### Changed
- `Web.Entities` reorder/archive/restore handlers now gate on `Scope.admin?` before any DB access — closes the missing-auth gap surfaced in PR #11 review.
- Card-view duplication in `Web.DataNavigator` collapsed via the `:draggable` attr on `<.draggable_list>` — ~80 lines removed.
- `position_update_query/2` raises `ArgumentError` on non-binary scope values (was silently fall-through).
- `ensure_manual_sort/1` logs at `Logger.error` and surfaces a warning flash when the sort-mode flip fails — admins now see the silent setting-flip outcome instead of the failure being swallowed.

### Added
- Audit row shape table in AGENTS.md documenting `actor_uuid` / `resource_uuid` / `metadata` conventions across entity and entity_data activity rows.
- Race-tolerance comment on `maybe_add_entity_position/1` documenting the concurrent-position-conflict resolution strategy.

## 0.1.6 - 2026-04-29

### Removed
- `PhoenixKitEntities.Migrations.V1` — dead code with zero callers in `lib/`, `test/`, or the host app. Entity tables are owned entirely by core PhoenixKit (`V17` creates them; `V40` / `V58` / `V67` / `V74` / `V81` evolve them). Host apps that were calling `Migrations.V1.up/1` directly should switch to `PhoenixKit.Migrations.up()`. **Note:** technically a breaking change for any standalone host that imported the V1 module, but in practice no known callers exist.
- `test/support/postgres/migrations/` — 210 lines of hand-rolled DDL deleted. Test schema now built by running core's versioned migrations directly via `Ecto.Migrator.run(TestRepo, [{0, PhoenixKit.Migration}], :up, ...)` — same call the host app makes in production. Schema drift between test and prod is now impossible by construction.

### Changed
- `Web.DataForm`, `Web.EntityForm`, `Web.EntitiesSettings` now defer DB queries from `mount/3` to `handle_params/3` — closes the still-open Phoenix iron-law follow-up from PR #9 across the remaining three admin LVs. All five admin LVs now compliant.
- `mount_data_form` / `mount_entity_form` / `mount_data_presence` / `mount_entity_presence` helpers renamed to `hydrate_*` to reflect that they fill data assigns rather than couple to the `mount/3` callback. `connected?(socket)` gating preserved exactly so presence still only initializes on the WebSocket pass.
- `entities_settings.ex`: 8-key settings map consolidated through a private `load_settings/0` helper, deduplicating the inline copy in `handle_event("save", ...)`.

### Fixed
- Test fixtures in `mirror/importer_test.exs` and `mix_tasks/import_test.exs` updated to match the real `phoenix_kit_users` schema: `account_type = 'person'` (was `'personal'`, which the production CHECK constraint rejects), `hashed_password` non-null, `inserted_at` / `updated_at` non-null. The previous hand-rolled test migration had been more permissive than production and was masking these latent bugs.

## 0.1.5 - 2026-04-28

### Fixed
- `entity_form_controller.ex`: replace `entity.id` with `entity.uuid` (lines 243 + 342) — primary key is `:uuid`, the previous reference would have crashed every public-form submission with `KeyError`
- `entity_form_controller.ex`: replace runtime-bound `logger.warning(...)` with `Logger.warning(...)` macro call — variable-bound macro dispatch raised `UndefinedFunctionError` on every `save_log` security flag

### Added
- `PhoenixKitEntities.Errors` module — central atom→message dispatcher for the 10 user-facing error categories surfaced by the admin LVs and public form
- Activity logging on every entity + entity_data CRUD path (create / update / delete / bulk operations / module toggle), with `actor_uuid` threaded from caller opts
- Public-form security hardening — X-Forwarded-For RFC1918 rejection (loopback / link-local / multicast / private-network octets), metadata size cap (`@metadata_string_cap 255`), browser/OS/device parsing
- `Mirror.Storage` filesystem path containment via `Path.expand` + boundary-prefix check
- Test infrastructure — `LiveCase`, `DataCase`, `Hooks`, test endpoint / router / layouts; supports the full LV admin smoke test suite
- 32 LiveView smoke tests across `Web.Entities`, `Web.EntityForm`, `Web.DataNavigator`, `Web.DataForm`, `Web.EntitiesSettings`
- Coverage push from 31.39% baseline to 75.14% across 5 quality batches (684 tests, 0 failures, 5/5 stable)

### Changed
- `Web.Entities` and `Web.DataNavigator` now defer DB queries from `mount/3` to `handle_params/3` — avoids the duplicate-query-on-mount Phoenix iron-law violation
- `ActivityLog` rescue shape canonicalised: `Postgrex.Error -> :ok`, `DBConnection.OwnershipError -> :ok`, fallback `error -> Logger.warning(...)`, `catch :exit, _ -> :ok`
- `Mirror.Storage` rescues narrowed from bare `rescue _` to `[ArgumentError, RuntimeError, FunctionClauseError]` for path operations
- `UrlResolver` rescues narrowed to a six-class DB-scoped list (no bare `_` catches)
- `FieldTypes.description_for/1` literal-clause helper introduced so gettext extraction works on all 12 type descriptions
- `handle_info` catch-alls promoted from silent ignore to `Logger.debug` across all 5 admin LVs
- `@spec` backfill on `routes.ex` (3 functions) and `sitemap_source.ex` (5 callbacks)
- `mix.exs` `test_coverage: [ignore_modules: [...]]` filter so coverage tracks production code, not test-support boilerplate

### Removed
- `PhoenixKitEntities.Web.DataView` — unrouted module with no callers anywhere in the workspace; verified via grep + ast-grep across `phoenix_kit_entities`, `phoenix_kit` core, and `phoenix_kit_parent`. Recoverable from git history if a public-display feature materialises later

## 0.1.4 - 2026-04-24

### Added
- `PhoenixKitEntities.UrlResolver` module — extracted URL pattern resolution and locale prefixing from `SitemapSource` into a shared helper
- `EntityData.public_path/3` and `public_url/3` — locale-aware public URL helpers with translated-slug support (`data[locale]["_slug"]`)
- `PhoenixKitEntities.list_entity_summaries/1` — lightweight sidebar query with `:lang` option
- `entities_children/2` arity on the sidebar callback for future phoenix_kit core releases that pass locale explicitly
- `PhoenixKitEntities.ActivityLog` — internal helper that logs entity and entity_data mutations through the optional `PhoenixKit.Activity` context
- README sections documenting multi-language support and public URL resolution
- Unit tests for `UrlResolver`, `public_path/3` / `public_url/3`, multilang field resolution, and per-locale sidebar cache invalidation

### Changed
- Admin LiveViews (`Web.Entities`, `Web.DataNavigator`, `Web.DataForm`) now thread the current locale through entity lookups so translated `display_name` / `display_name_plural` / `description` render in the admin UI
- Sidebar `entities_children` caches per-locale ETS entries; `invalidate_entities_cache/0` now match-deletes every locale variant instead of the single atom key
- `SitemapSource` delegates URL construction to `UrlResolver` while keeping its "prefix every language" policy
- `resolve_language/2` and `resolve_languages/2` are nil-safe so callers can pass an optional locale without a pre-check

## 0.1.3 - 2026-04-11

### Fixed
- Remove misleading Data View route override example (anti-pattern)
- Add routing anti-pattern warning to AGENTS.md
- Fix version mismatch between mix.exs and module function

## 0.1.2 - 2026-04-02

### Fixed
- Migrate select elements to daisyUI 5 label wrapper pattern
- Remove deprecated `select-bordered` class for daisyUI 5 compatibility

## 0.1.1 - 2026-04-01

### Fixed
- Fix compilation error: replace undefined `content_status_badge` with `status_badge` from PhoenixKit core components

## 0.1.0 - 2026-03-24

### Added
- Extract Entities module from PhoenixKit into standalone `phoenix_kit_entities` package
- Implement `PhoenixKit.Module` behaviour with all required callbacks
- Add `PhoenixKitEntities` schema for dynamic entity definitions with JSONB field schemas
- Add `PhoenixKitEntities.EntityData` schema for data records with JSONB field values
- Add `PhoenixKitEntities.FieldTypes` registry with 12 supported field types
- Add `PhoenixKitEntities.FormBuilder` for dynamic form generation and validation
- Add `PhoenixKitEntities.Events` PubSub helpers for entity/data lifecycle events
- Add `PhoenixKitEntities.Presence` and `PresenceHelpers` for collaborative editing with FIFO locking
- Add admin LiveViews: Entities, EntityForm, DataNavigator, DataForm, EntitiesSettings
- Add route module with `admin_routes/0`, `admin_locale_routes/0`, and public form routes
- Add `css_sources/0` for Tailwind CSS scanning support
- Add migration module (v1) with `IF NOT EXISTS` for both tables (run by parent app)
- Add public form component with honeypot, time-based validation, and rate limiting
- Add sitemap integration for published entity data
- Add filesystem mirroring (export/import) with mix tasks
- Add multi-language support (auto-enabled with 2+ languages)
- Add behaviour compliance test suite
- Add unit tests for changesets, field types, events, form validation, HTML sanitization, multilang
