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
createdb phoenix_kit_entities_test  # First-time test DB setup — see "Testing" below for the PGDATABASE/PGPOOL override
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

## Local cross-repo development

`phoenix_kit` (and any sibling `phoenix_kit_*` dep) resolves from Hex by
default. To build or test this module against a **local checkout** of a
dependency — e.g. an unpublished core change — export `<APP>_PATH` and Mix
swaps the Hex pin for a `path:` + `override: true` dep at resolve time:

```bash
PHOENIX_KIT_PATH=../phoenix_kit mix test     # this module against local core
```

The variable name is the dep's app name upper-cased with `_PATH` appended
(`:phoenix_kit` -> `PHOENIX_KIT_PATH`). Today only `:phoenix_kit` is wrapped;
wrap a sibling dep in `pk_dep/3` to give it the same `<APP>_PATH` switch.
A blank or unset value falls back to the published Hex pin, so
`mix hex.publish` and CI resolve exactly as before.

The override is gated on the env var, not on the repo: `mix.exs` ships in the
package and `pk_dep/3` reads the var wherever this lib is resolved. Setting
`PHOENIX_KIT_PATH` therefore also redirects `phoenix_kit` for any downstream
project that consumes `phoenix_kit_entities` while the var is exported — keep
it scoped to the shell where you're actually doing cross-repo work.

Implemented via `pk_dep/3` in `mix.exs` — never hand-edit a `phoenix_kit*`
dep into a `path:` tuple (a committed path dep ships a broken package); set
the env var instead.

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
- Migrations are owned by core PhoenixKit (`V17` creates the tables;
  `V40` / `V58` / `V67` / `V74` / `V81` / `V108` evolve them). No
  module-owned DDL anywhere — the host app runs
  `PhoenixKit.Migrations.up()` and gets everything.

### Drag-and-drop reorder API

Both lists carry an integer `position` column (V81 for entity_data,
V108 for entities) that drives manual sort.

- `Entities.reorder_entities(ordered_uuids, opts)` — re-indexes the
  entity definitions to positions `1..N`. Logs `entity.reordered`,
  broadcasts `:entity_updated` for sidebar cache invalidation. Capped
  at 1000 uuids; oversized rejects with `{:error, :too_many_uuids}`
  AND audit-logs the rejection (`db_pending: true`,
  `rejected: "too_many_uuids"`).
- `EntityData.reorder(entity_uuid, ordered_uuids, opts)` — re-indexes
  records within one entity. The DB layer enforces the entity_uuid
  scope so a stray cross-entity uuid in the input list cannot rewrite
  positions in the wrong scope (every per-uuid `update_all`
  AND-filters on `entity_uuid`). Same 1000-cap + dedup behavior.
- Both functions log on `:ok` AND `:error` branches; the error branch
  carries `db_pending: true` so the audit trail covers user-initiated
  intent even when the transaction rolls back.
- The `:ok` row is emitted only when the transaction actually wrote a
  row. `EntityData.reorder/3` counts rows written, not pairs submitted —
  a uuid naming a record in another entity matches nothing (that is what
  the scope is for), and neither does a concurrently deleted one — so a
  save that moved nothing records nothing rather than logging a
  non-event.
- LV call sites (`Web.Entities`, `Web.DataNavigator`) thread
  `actor_opts(socket)` so the activity rows pin `actor_uuid`. The
  DataNavigator auto-flips `sort_mode` to `"manual"` on the first
  drag and emits a `Logger.warning` so ops can see the implicit
  setting change.

**Audit row shape** — every reorder path emits an `ActivityLog` row:

| Field                  | Success                           | DB error                | Rejected (`:too_many_uuids`) |
|------------------------|-----------------------------------|-------------------------|-------------------------------|
| `action`               | `entity.reordered` / `entity_data.reordered` | same              | same                          |
| `actor_uuid`           | from caller opts                  | same                    | same                          |
| `resource_type`        | `entity` / `entity_data`         | same                    | same                          |
| `resource_uuid`        | first uuid in list                | first uuid in list      | nil                           |
| `metadata.count`       | rows written                      | n (pairs)               | n (pairs)                     |
| `metadata.entity_uuid` | data path only                    | data path only          | data path only                |
| `metadata.db_pending`  | absent                            | `true`                  | `true`                        |
| `metadata.rejected`    | absent                            | absent                  | `"too_many_uuids"`            |

### Soft-delete (trash) for EntityData

EntityData records support soft-delete via the `status` column with the
sentinel `"trashed"` (workspace convention — same as publishing posts).
The row stays alive in the DB so parent-app FK references stay
satisfied; default `list_*` queries hide trashed rows.

**Why this matters.** Parent apps commonly use entity_data records as
controlled vocabularies (e.g. `orders.status_uuid → phoenix_kit_entity_data(uuid)`,
NOT NULL). Hard-deleting via `Repo.delete` triggers the parent's FK
action — `:nilify_all` violates NOT NULL, `:restrict` blocks, `:delete_all`
cascades — and the admin sees an opaque 500. Soft-delete sidesteps all
three: the row survives, the parent's FK keeps resolving, and the
admin can restore later or permanently delete once references clear.

**Public API:**

- `EntityData.trash/2` — flips status to `"trashed"`. Refuses
  `{:error, :already_trashed}` for already-trashed rows. Logs
  `entity_data.trashed`.
- `EntityData.restore_from_trash/2` — flips trashed → published.
  Refuses `{:error, :not_trashed}` for non-trashed rows. Logs
  `entity_data.restored`.
- `EntityData.bulk_trash/2` + `bulk_restore_from_trash/2` — batched
  versions; emit ONE `entity_data.bulk_trashed` /
  `entity_data.bulk_restored` audit row per call. Skip already-state
  rows via the WHERE clause.
- `EntityData.list_trashed_by_entity/2` + `trashed_count/1` — surface
  trashed rows for the admin trash bin.
- `EntityData.delete/2` + `bulk_delete/2` — hard-delete.
  **Wrapped in a Postgrex / Ecto.ConstraintError rescue** that catches
  FK / NOT NULL violations and returns
  `{:error, :referenced_by_external}` so the admin LV can render a
  friendly flash via `Errors.message(:referenced_by_external)` instead
  of 500. Re-raises any other constraint error so real bugs surface.

**Default-list filtering.** `list_all`, `list_by_entity`,
`search_by_title`, `count_by_entity`, and `get_data_stats` exclude
trashed by default; pass `include_trashed: true` to surface them
(used by reverse-reference checks and the admin trash view).
`get_by_slug/3` is intentionally NOT filtered — slug uniqueness must
survive trashing so a restored row doesn't collide with a
freshly-created replacement.

**Reverse-reference hook.** Parent apps with FK columns to
entity_data can declare count callbacks via `Application` config:

```elixir
config :phoenix_kit_entities,
  reverse_references: [
    {"order_status", &MyApp.Orders.count_orders_with_status/1},
    {"sub_order_status", &MyApp.Orders.count_sub_orders_with_status/1}
  ]
```

`EntityData.count_external_references/1` resolves the entity name to
matching callbacks and sums them. Multiple callbacks per entity name
are fine — they all contribute (e.g. `orders` + `audit_log` both
referencing the same `order_status` add together). Informational
only, **NOT a delete-blocker** — soft-delete is safe regardless of
the count.

The `:reverse_references` key lives in the **global** OTP application
env, so in an umbrella where two parent apps both define a callback
for the same entity name (e.g. both register `"order_status"`), both
callbacks fire on every `count_external_references/1` call and the
totals add. For a single-tenant deploy this is irrelevant; multi-
tenant hosts should pick distinct entity names per app or accept
the cross-pollination.

The 1-arity form preloads `:entity` per call. When rendering many
records (admin trash bin, list views), prefer the 2-arity form
`count_external_references(record, entity)` and load the entity
once outside the loop to skip the N+1.

**Admin UX (DataNavigator).** Bulk Delete now soft-trashes by default;
permanent delete is a separate action available only from the Trash
filter view (`status=trashed` query param). Per-record buttons branch
by status: published/draft → Archive + Trash, archived → Restore +
Trash, trashed → Restore-from-trash + Delete-forever. The
`toggle_status` cycle skips trashed (Restore is the only escape).

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
where verb is one of `created`, `updated`, `deleted`, `trashed`,
`restored`, `bulk_status_changed`, `bulk_deleted`, `bulk_trashed`,
`bulk_restored`, `translation_set`. Module toggles use
`"module.entities.{enabled|disabled}"`. Note `entity_data.deleted`
fires for hard-delete; `entity_data.trashed` for soft-delete — keep
them distinct so audit consumers can tell which path ran.

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

This module owns **no** DDL. The two tables it relies on
(`phoenix_kit_entities` and `phoenix_kit_entity_data`) are created and
maintained by core PhoenixKit's versioned migrations: `V17` creates
them; `V40` / `V58` / `V67` / `V74` / `V81` evolve them (UUID PK
addition, timestamp columns, FK conversions, `position` column).

The host app runs `PhoenixKit.Migrations.up()` once and gets the full
schema. The test suite does the same against an isolated test repo
(see `test/test_helper.exs`) — same call, same migrations, no chance
of drift.

UUIDv7 primary keys throughout. The `uuid_generate_v7()` Postgres
function is created by core's V40.

## Testing

### Setup

By default this module points at its own test database
(`phoenix_kit_entities_test`) — that's only the default, not a
guarantee; see the `PGDATABASE` override below. Create it once:

```bash
createdb phoenix_kit_entities_test
```

If the DB is absent, integration tests auto-exclude via the
`:integration` tag (see `test/test_helper.exs`) — unit tests still run.

`database:` / `pool_size:` in `config/test.exs` read `PGDATABASE` /
`PGPOOL` instead, falling back to the hardcoded name above and
`System.schedulers_online() * 2` when unset — same mechanism core
`phoenix_kit`'s `config/test.exs` uses. Set both to point this suite
at a database it doesn't own and can't `CREATEDB` for itself, e.g. a
shared instance also used by sibling `phoenix_kit_*` modules:

```bash
PGDATABASE=migration_test_db PGPOOL=6 mix test
```

**Caution:** if `PGDATABASE` points at a database other modules also
use, don't combine it with `PHOENIX_KIT_PATH=../phoenix_kit` (local
core checkout) — `test_helper.exs`'s migration call would then run
*that* core's migration chain against the shared database, moving its
schema for every other module pointed at the same `PGDATABASE`, not
just this suite.

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

Schema setup runs core's versioned migrations directly via
`Ecto.Migrator.run(TestRepo, [{0, PhoenixKit.Migration}], :up, ...)`
in `test_helper.exs` — no module-owned test DDL.

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

This project follows [Semantic Versioning](https://semver.org/).

### Version locations

The **package version** lives in **one** place — `@version` in `mix.exs`. It
drives the Hex release, the `CHANGELOG.md` heading, the git tag, and `source_ref`
for the docs. Bumping it (plus the CHANGELOG entry and tag) is the whole release.

`lib/phoenix_kit_entities.ex`'s `def version/0` is the `PhoenixKit.Module`
behaviour callback, **not** the package version. It is versioned independently
(currently `"0.1.4"`) and is intentionally not bumped on every release. The only
test that touches it — `test/phoenix_kit_entities/context_extras_test.exs` —
asserts `is_binary(Entities.version())`, not a specific value, so a package bump
does not require changing it or any test. (`phoenix_kit_entities_test.exs` does
not assert the version.)

### Tagging & GitHub releases

Tags use a **`v` prefix** (e.g. `v0.2.6`), matching `source_ref: "v#{@version}"`
in `mix.exs` and every recent release (`v0.2.1`, `v0.2.3`, `v0.2.4`, `v0.2.6`).
Only a handful of the earliest tags are bare (`0.1.0`, `0.1.4`); new tags follow
the `v` form.

```bash
git tag -a v0.2.6 -m "Release 0.2.6"
git push origin v0.2.6
gh release create v0.2.6 \
  --title "0.2.6 - 2026-06-24" \
  --notes "$(changelog body for this version)"
```

Order matters: commit → push → `mix hex.publish` → **only then** tag. Never tag
before a successful publish or before all changes are committed and pushed — tags
are immutable pointers.

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
