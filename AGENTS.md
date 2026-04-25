# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Project Overview

PhoenixKit Entities — a standalone PhoenixKit plugin module providing
dynamic content types with flexible JSONB field schemas. Extracted from
phoenix_kit core into its own package. Implements the
`PhoenixKit.Module` behaviour for auto-discovery by a parent Phoenix
application.

## What This Module Does NOT Have (by design)

This module is the dynamic-content-types layer for PhoenixKit. It
deliberately does not include:

- **Per-entity DB tables** — every entity type lives in the same
  `phoenix_kit_entity_data` JSONB row shape. Schema flexibility comes
  from the `fields_definition` JSONB column on `phoenix_kit_entities`,
  not from running new migrations per entity.
- **Frontend rendering of records** — the parent Phoenix app owns the
  public LiveView/controller that displays a record at
  `/products/my-item`. This module only provides the URL helpers
  (`EntityData.public_path/3`, `public_url/3`, `public_alternates/3`)
  and the route-resolution logic.
- **Authentication on public form submissions** — the public POST
  endpoint at `/entities/:entity_slug/submit` accepts un-authed
  submissions on purpose (it's the public-form contract). Defense is
  honeypot + minimum submission time + rate limiting, not auth.
- **Per-entity push-notification or webhook delivery** — `Events`
  broadcasts to PubSub for in-app reactivity. External webhook
  delivery is out of scope.
- **Visual schema editor for fields** — fields are added one-at-a-time
  via the entity form. No drag-to-canvas builder.

## Common Commands

### Setup & Dependencies

```bash
mix deps.get                # Install dependencies
createdb phoenix_kit_entities_test  # First-time test DB setup
```

### Testing

```bash
mix test                                        # Run all tests
mix test test/phoenix_kit_entities_test.exs     # Specific file
mix test test/file_test.exs:42                  # Specific test by line
mix test --exclude integration                  # Unit tests only (no DB)
for i in $(seq 1 10); do mix test; done         # 10× stability check
```

### Code Quality

```bash
mix format              # Format code (imports Phoenix LiveView rules)
mix credo --strict      # Lint (strict mode)
mix dialyzer            # Static type checking
mix precommit           # compile + format + credo --strict + dialyzer
mix docs                # Generate documentation
```

## Dependencies

This is a **library** (not a standalone Phoenix app). The full chain:

- `phoenix_kit` (`~> 1.7`, Hex) — Module behaviour, Settings API,
  RepoHelper, Dashboard tabs, Activity logging, shared web components,
  Multilang helpers
- `phoenix_live_view` (`~> 1.0`) — admin LiveViews
- `lazy_html` (test only) — HTML parser used by `Phoenix.LiveViewTest`
  for smoke tests

## Architecture

This is a **PhoenixKit module** that implements the `PhoenixKit.Module`
behaviour. It depends on the host PhoenixKit app for Repo, Endpoint,
and Settings.

### How It Works

1. Parent app adds this as a dependency in `mix.exs`
2. PhoenixKit scans `.beam` files at startup and auto-discovers modules
   (zero config)
3. `route_module/0` returns `PhoenixKitEntities.Routes` which defines
   all admin LiveView routes via `admin_routes/0` /
   `admin_locale_routes/0`, plus public form routes via `generate/1`
4. Settings are persisted via `PhoenixKit.Settings` API (DB-backed in
   parent app)
5. Permissions are declared via `permission_metadata/0` and checked via
   `Scope.has_module_access?/2`
6. `css_sources/0` returns `[:phoenix_kit_entities]` so the installer
   adds Tailwind `@source` directives

### Key Modules

- **`PhoenixKitEntities`** (`lib/phoenix_kit_entities.ex`) — Main
  module: Ecto schema for entity definitions + `PhoenixKit.Module`
  behaviour callbacks. Both the schema and the entry point.
- **`PhoenixKitEntities.EntityData`**
  (`lib/phoenix_kit_entities/entity_data.ex`) — Ecto schema and CRUD
  for data records. Owns `public_path/3`, `public_url/3`, and
  `public_alternates/3`.
- **`PhoenixKitEntities.FieldTypes`**
  (`lib/phoenix_kit_entities/field_types.ex`) — Registry of 12
  supported field types with validation and helpers.
- **`PhoenixKitEntities.FormBuilder`**
  (`lib/phoenix_kit_entities/form_builder.ex`) — Dynamic form
  generation from entity field definitions + data validation.
- **`PhoenixKitEntities.Events`**
  (`lib/phoenix_kit_entities/events.ex`) — PubSub helpers for
  entity/data lifecycle events and collaborative editing. All topic
  strings live here as named functions; never hardcode topics in
  callers.
- **`PhoenixKitEntities.Routes`**
  (`lib/phoenix_kit_entities/routes.ex`) — Admin LiveView routes +
  public form submission endpoint. Registered via `route_module/0`.
- **`PhoenixKitEntities.UrlResolver`**
  (`lib/phoenix_kit_entities/url_resolver.ex`) — Shared URL-pattern
  resolution (entity settings → router introspection → per-entity
  settings → global pattern → fallback). Used by `SitemapSource` and
  by `EntityData.public_path/3`. Settings lookups rescue narrow
  DB-availability exceptions (`DBConnection.ConnectionError`,
  `Postgrex.Error`, `Ecto.QueryError`, `RuntimeError`,
  `ArgumentError`) so URL generation degrades gracefully when
  Settings are missing or the repo isn't started — real bugs
  (`KeyError`, `FunctionClauseError`) still surface.
- **`PhoenixKitEntities.SitemapSource`**
  (`lib/phoenix_kit_entities/sitemap_source.ex`) —
  `PhoenixKit.Modules.Sitemap.Sources.Source` implementation.
  Delegates pattern resolution to `UrlResolver`; keeps a "prefix every
  language" policy for hreflang-correct sitemap entries.
- **`PhoenixKitEntities.Presence` / `PresenceHelpers`** — FIFO
  collaborative editing locks and presence tracking.
- **`PhoenixKitEntities.Mirror.*`** — Filesystem export/import of
  entity definitions and data (per-entity toggles in
  `entity.settings`).
- **`PhoenixKitEntities.Web.*`** — Admin LiveViews. PhoenixKit wraps
  these in the admin layout automatically.
- **`PhoenixKitEntities.Controllers.EntityFormController`** — Public
  form submissions (honeypot, minimum-time, rate limiting).
- **`PhoenixKitEntities.ActivityLog`**
  (`lib/phoenix_kit_entities/activity_log.ex`) — Thin wrapper around
  `PhoenixKit.Activity.log/1` with the `"entities"` module key,
  guarded by `Code.ensure_loaded?/1` and a rescue so logging failures
  never crash the primary mutation. See "Activity Logging Pattern"
  below.
- **`PhoenixKitEntities.Errors`**
  (`lib/phoenix_kit_entities/errors.ex`) — Atom-to-gettext dispatcher.
  Public-API error returns use atoms (`:cannot_remove_primary`,
  `:not_multilang`, `:entity_not_found`) and tagged tuples
  (`{:invalid_field_type, type}`, `{:user_entity_limit_reached, max}`)
  so callers can pattern-match locale-agnostic; LiveView call sites
  pipe the reason through `Errors.message/1` for the user-facing
  string. See `test/phoenix_kit_entities/errors_test.exs` for the
  exhaustive per-atom test that pins each translated string.

### Two-Table Database Design

- `phoenix_kit_entities` — Entity definitions (blueprints) with JSONB
  `fields_definition` and `settings`
- `phoenix_kit_entity_data` — Data records (instances) with JSONB
  `data` and `metadata` field values
- Both use UUIDv7 primary keys
- Migration in `PhoenixKitEntities.Migrations.V1` uses
  `IF NOT EXISTS` for idempotency

### Activity Logging Pattern

Mutations log via `PhoenixKitEntities.ActivityLog.log/1`, which wraps
`PhoenixKit.Activity.log/1` with the `"entities"` module key. The
wrapper:

```elixir
defp log(action, payload) do
  if Code.ensure_loaded?(PhoenixKit.Activity) do
    payload
    |> Map.put(:module, "entities")
    |> Map.put_new(:action, action)
    |> PhoenixKit.Activity.log()
  else
    :activity_unavailable
  end
rescue
  e ->
    Logger.warning("[Entities] Activity logging error: #{Exception.message(e)}")
    {:error, e}
end
```

Notification-side wiring lives in `notify_entity_event/2`
(`phoenix_kit_entities.ex`) and `notify_data_event/2`
(`entity_data.ex`). They're piped after every CRUD repo call so
activity logging only fires on `:ok` and the `:error` tuple flows
through unchanged.

Action-atom convention: `"entity.{verb}"` and `"entity_data.{verb}"`
where verb is one of `created`, `updated`, `deleted`,
`bulk_status_changed`, `bulk_deleted`, `translation_set`. Module
toggles use `"module.entities.{enabled|disabled}"`.

PII guardrail at the source: never log `email`, `phone`, free-text
`description` fields, raw `data` JSONB blobs, or any user-typed
field. Safe metadata: `name`, `display_name`, `slug`, `status`,
derived counts, FK uuids.

### Settings Keys

- `entities_enabled` (boolean) — global on/off for the module
- `entities_mirror_path` (string) — base directory for filesystem
  mirroring of entity definitions and data (default:
  `priv/entities` under the parent app)
- `sitemap_entities_pattern` (string, optional) — global URL pattern
  template for entity records when no per-entity pattern is set
  (e.g., `"/:entity_name/:slug"`)
- `sitemap_entity_<name>_pattern` (string, optional) — per-entity URL
  pattern override
- `sitemap_entity_<name>_index_path` (string, optional) — per-entity
  index page URL
- `sitemap_entities_auto_pattern` (boolean, optional) — when true,
  fall back to `/<entity_name>` as the index path

### File Layout

```
lib/phoenix_kit_entities.ex                       # Main module + entity schema
lib/phoenix_kit_entities/
├── activity_log.ex                              # ActivityLog.log/1 wrapper
├── entity_data.ex                               # Data-record schema + public URL helpers
├── events.ex                                    # PubSub topic constants + broadcast helpers
├── field_types.ex                               # 12 field types + validators
├── field_type.ex                                # Single field type struct
├── form_builder.ex                              # Dynamic form generation
├── presence.ex / presence_helpers.ex            # FIFO editing locks
├── routes.ex                                    # Admin + public route declarations
├── sitemap_source.ex                            # Sitemap.Source implementation
├── url_resolver.ex                              # Shared URL pattern resolution
├── components/                                  # Function components
├── controllers/entity_form_controller.ex        # Public form submission endpoint
├── migrations/v1.ex                             # Idempotent table-creation migration
├── mirror/{exporter,importer,storage}.ex        # Filesystem mirror subsystem
├── mix_tasks/{export,import}.ex                 # Mix tasks for bulk export/import
└── web/                                         # Admin LiveViews
    ├── entities.ex                              # Entity list
    ├── entity_form.ex                           # Entity create/edit form
    ├── data_navigator.ex                        # Data record browser
    ├── data_form.ex                             # Data record create/edit form
    ├── entities_settings.ex                    # Module settings + import/export modal
    └── hooks.ex                                 # on_mount hook (assigns + auth)
```

## Critical Conventions

- **Module key** must be consistent across all callbacks: `"entities"`
- **Tab IDs**: prefixed with `:admin_` (e.g., `:admin_entities`)
- **URL paths**: use hyphens, not underscores (e.g., `"entities"`)
- **Navigation paths**: always use `PhoenixKit.Utils.Routes.path/1`,
  never relative paths
- **`enabled?/0`**: rescues errors AND catches `:exit` signals
  (sandbox shutdown raises `:exit`, not an exception). Returns
  `false` as fallback (DB may not be available). Same pattern lives
  in `safe_count/1` (used by `get_config/0`) so module-level
  callbacks don't crash outside a sandbox checkout.
- **`enable_system/0` and `disable_system/0`**: use `module_key()`
  not hardcoded strings; both log
  `module.entities.{enabled|disabled}` activity rows
- **LiveViews use `PhoenixKitWeb` macros** —
  `use PhoenixKitWeb, :live_view` and `use PhoenixKitWeb, :controller`
  are correct since this module depends on `phoenix_kit` which
  provides them. Never wrap admin LiveViews with `LayoutWrapper` —
  PhoenixKit auto-applies admin layout via on_mount hook. Wrapping
  causes double sidebars.
- **LiveView assigns** available in admin pages:
  `@phoenix_kit_current_scope`, `@current_locale`, `@url_path`
- **Entity names** must be snake_case, start with letter, 2-50 chars:
  `^[a-z][a-z0-9_]*$`
- **Field definitions** require string keys:
  `%{"type" => "text", "key" => "name", "label" => "Name"}`
- **Inline templates** — All LiveView templates use inline `~H`
  sigils (no separate `.heex` files) for reliable Tailwind CSS
  scanning
- **Multilang for entity metadata** — `display_name`,
  `display_name_plural`, and `description` are translatable via
  `entity.settings["translations"]`. Every entity query function
  (`list_entities`, `get_entity_by_name`, `list_entity_summaries`, …)
  accepts an optional `lang:` keyword that returns the struct with
  those fields resolved. Translation-key lookup is normalized via
  `DialectMapper.extract_base/1` so dialect/base mismatches
  (`"es"` querying `"es-ES"` rows) still resolve. Admin LiveViews
  thread `lang: @current_locale` to dogfood the pattern;
  `Web.EntityForm` and `Web.EntitiesSettings` intentionally keep raw
  primary-language reads because they manage canonical identity.
- **Sidebar locale propagation** — `entities_children/1` has no direct
  access to the current locale from the dashboard registry, so it
  reads `Gettext.get_locale(PhoenixKitWeb.Gettext)` at render time.
  The ETS cache is keyed by `{@entities_cache_key, locale}`;
  `invalidate_entities_cache/0` uses `:ets.match_delete/2` to clear
  every locale variant on mutations. `entities_children/2` accepts an
  explicit locale from forward-compatible core releases that pass it.
- **Public URL helpers** — `EntityData.public_path/3` and
  `public_url/3` build locale-aware public URLs for records, reusing
  `UrlResolver`. Locale policy matches `PhoenixKit.Utils.Routes.path/2`:
  `nil` locale / single-language / primary language → no prefix; other
  locales → `/<base>/…`. `EntityData.public_alternates/3` returns
  `%{canonical, alternates: [%{locale, href}, ..., %{locale: "x-default", href}]}`
  for SEO sites that need to declare hreflang/canonical alongside
  the prefixed URLs.
- **Public form controller defense** — the public POST at
  `/entities/:entity_slug/submit` is intentionally un-authed.
  Protection is honeypot field + minimum submission time + rate
  limiting (Hammer per-IP-per-entity bucket). The IP used for the
  rate-limit key is validated against an IPv4 format regex with
  RFC1918/loopback rejection so `X-Forwarded-For` spoofing can't
  multiply per-fake-IP buckets. Stored metadata (user-agent, referer)
  is capped at 255 chars to prevent JSONB bloat.
- **Mirror path containment** — `mirror/storage.ex` reads its base
  directory from the `entities_mirror_path` setting. The path is
  resolved through `Path.expand/1` and validated against the parent
  app's `priv/entities` root so an admin-edited setting can't escape
  to write entity exports under arbitrary filesystem locations.

## Routing: Single Page vs Multi-Page

> ⚠️ **Never hand-register plugin LiveView routes in the parent app's
> `router.ex`.** PhoenixKit injects module routes into its own
> `live_session :phoenix_kit_admin` automatically. A hand-written
> route sits outside that session and (a) loses the admin layout
> (`:phoenix_kit_ensure_admin` only applies it inside the session),
> (b) crashes the socket on cross-page navigation
> (`navigate event failed because you are redirecting across
> live_sessions`). Use the route module pattern.

This module uses the **route module pattern** because it has multiple
admin LiveViews per page. All routes are declared in
`PhoenixKitEntities.Routes`:

- `admin_locale_routes/0` — localized admin routes (with `:locale`
  prefix)
- `admin_routes/0` — non-localized admin routes (must mirror
  `admin_locale_routes/0` with distinct `:as` aliases)
- `generate/1` — public POST `/entities/:entity_slug/submit`

`admin_tabs/0` does NOT have a `live_view:` field — the route module
handles all routing.

> **`admin_routes/0` and `admin_locale_routes/0` can only contain
> `live` declarations.** Their quoted blocks splice directly inside
> Phoenix's `live_session :phoenix_kit_admin do … end` block. Phoenix
> rejects controllers (`get`, `post`), `forward`, nested `scope`, and
> `pipe_through` at compile time. Public-facing controllers go in
> `generate/1` — see `routes.ex` for the existing pattern.

## Tailwind CSS Scanning

This module implements `css_sources/0` returning
`[:phoenix_kit_entities]`. PhoenixKit's installer
(`mix phoenix_kit.install`) discovers this and adds `@source`
directives to the parent's `app.css`. Without this, Tailwind purges
CSS classes from our templates.

## Database & Migrations

The module owns two tables (`phoenix_kit_entities` and
`phoenix_kit_entity_data`), declared in
`PhoenixKitEntities.Migrations.V1`. The migration uses `IF NOT EXISTS`
guards so it's idempotent and safe to re-run. The parent
`phoenix_kit` project also re-applies these tables in its versioned
migrations (V17), so most production deploys see them created via
core. The local `V1` migration is the source of truth for the test
schema and for standalone host apps that don't use core's installer.

UUIDv7 primary keys throughout. The
`uuid_generate_v7()` Postgres function comes from
`PhoenixKit.Migration.SQLHelpers.uuid_generate_v7_function/0` (core).
Test infra creates it directly — see `test/support/postgres/migrations/`.

## Testing

### Setup

This module owns its own test database (`phoenix_kit_entities_test`).
Create it once:

```bash
createdb phoenix_kit_entities_test
```

If the DB is absent, integration tests auto-exclude via the
`:integration` tag (see `test/test_helper.exs`) — unit tests still run.

The critical config wiring is in `config/test.exs`:

```elixir
config :phoenix_kit, repo: PhoenixKitEntities.Test.Repo
```

Without this, all DB calls through `PhoenixKit.RepoHelper` crash with
"No repository configured".

### Test infrastructure

- `test/support/test_repo.ex` — `PhoenixKitEntities.Test.Repo`
  (Ecto repo for tests)
- `test/support/data_case.ex` — `PhoenixKitEntities.DataCase` (sandbox
  setup, auto-tags `:integration` for tests with a `repo` reference)
- `test/support/live_case.ex` — `PhoenixKitEntities.LiveCase` (thin
  wrapper around `Phoenix.LiveViewTest` with router + endpoint wiring)
- `test/support/test_endpoint.ex` + `test_router.ex` +
  `test_layouts.ex` — minimal Phoenix plumbing so LiveViews can render
  under `Phoenix.LiveViewTest.live/2`. **`Test.Layouts.app/1` renders
  flashes** — required for asserting flash content via `live/2` after
  click events
- `test/support/activity_log_assertions.ex` —
  `PhoenixKitEntities.ActivityLogAssertions` (helpers
  `assert_activity_logged/2` and `refute_activity_logged/2` that
  query `phoenix_kit_activities` directly with action / actor_uuid /
  resource_uuid / metadata-subset matching)
- `test/support/hooks.ex` — `PhoenixKitEntities.Test.Hooks` (on_mount
  hook for injecting `phoenix_kit_current_scope` into LiveView mount
  via session, with `LiveCase.put_test_scope/2` + `fake_scope/1`
  helpers)
- `test/support/postgres/migrations/` — creates
  `phoenix_kit_entities`, `phoenix_kit_entity_data`,
  `phoenix_kit_settings`, `phoenix_kit_activities`, plus the
  `uuid_generate_v7()` function

### Running tests

```bash
mix test                                   # All tests (excludes :integration if no DB)
mix test test/phoenix_kit_entities_test.exs # Module behaviour tests only
mix test test/phoenix_kit_entities/web      # LiveView smoke tests only
for i in $(seq 1 10); do mix test; done    # Stability check
```

### Version compliance test

The test file verifies `module_key/0`, `module_name/0`, `version/0`,
`permission_metadata/0`, `admin_tabs/0`, and `css_sources/0`.

## External Dependencies (from phoenix_kit)

These are **not our modules** — they come from the `phoenix_kit`
dependency:

- `PhoenixKit.Modules.Languages` — language system integration
- `PhoenixKit.Modules.Languages.DialectMapper` — base/dialect locale
  normalisation (`extract_base/1`)
- `PhoenixKit.Modules.Sitemap.*` — sitemap behaviour/types
- `PhoenixKit.Utils.Multilang` — multi-language JSONB helpers
- `PhoenixKit.Utils.HtmlSanitizer` — XSS prevention
- `PhoenixKitWeb.*` — web components, Gettext, layout, icons
- `PhoenixKit.Settings`, `PhoenixKit.Dashboard.Tab`,
  `PhoenixKit.Users.Auth.*` — core APIs
- `PhoenixKit.Activity` — optional; gracefully degrades when absent
  (every `ActivityLog.log/1` call guards with `Code.ensure_loaded?/1`)

## Versioning & Releases

Releases (version bumps + CHANGELOG entries + tags) are **boss-only** —
Max handles release cuts personally. Don't auto-bump.

### Version locations

When bumping, the version must be updated in **three places**:

1. `mix.exs` — `@version` module attribute
2. `lib/phoenix_kit_entities.ex` — `def version, do: "x.y.z"`
3. `test/phoenix_kit_entities_test.exs` — version compliance test

### Tagging & GitHub releases

Tags use **bare version numbers** (no `v` prefix):

```bash
git tag 0.1.0
git push origin 0.1.0
gh release create 0.1.0 \
  --title "0.1.0 - 2026-03-24" \
  --notes "$(changelog body for this version)"
```

Never tag or release before all changes are committed and pushed —
tags are immutable pointers.

## Pull Requests

### Commit Message Rules

Start with action verbs: `Add`, `Update`, `Fix`, `Remove`, `Merge`.
**Do not include AI attribution or `Co-Authored-By` footers** — Max
handles attribution on his own.

### PR Reviews

PR review files go in
`dev_docs/pull_requests/{year}/{pr_number}-{slug}/` directory. Use
`{AGENT}_REVIEW.md` naming (e.g., `CLAUDE_REVIEW.md`,
`GEMINI_REVIEW.md`). Each PR folder gets a `FOLLOW_UP.md` summarising
how every finding was resolved (or explicitly skipped with rationale).
See `dev_docs/pull_requests/2026/8-multilang-metadata-and-public-urls/FOLLOW_UP.md`
for the canonical batch-fix shape and
`dev_docs/pull_requests/2026/5-fix-routing-docs/FOLLOW_UP.md` for the
no-findings stub.

Severity levels for review findings:

- `BUG - CRITICAL` — Will cause crashes, data loss, or security issues
- `BUG - HIGH` — Incorrect behavior that affects users
- `BUG - MEDIUM` — Edge cases, minor incorrect behavior
- `IMPROVEMENT - HIGH` — Significant code quality or performance issue
- `IMPROVEMENT - MEDIUM` — Better patterns or maintainability
- `NITPICK` — Style, naming, minor suggestions

## Pre-commit Commands

Always run before git commit:

```bash
mix precommit               # compile + format + credo --strict + dialyzer
```

## Two Module Types

- **Full-featured**: Admin tabs, routes, UI, settings (this module —
  five admin LiveViews + a public form controller)
- **Headless**: Functions/API only, no UI — still gets
  auto-discovery, toggles, and permissions (e.g., `phoenix_kit_ai`)
