# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Project Overview

PhoenixKit Entities — a standalone PhoenixKit plugin module providing dynamic content types with flexible JSONB field schemas. Extracted from phoenix_kit core into its own package. Implements the `PhoenixKit.Module` behaviour for auto-discovery by a parent Phoenix application.

## Common Commands

```bash
mix deps.get          # Install dependencies
mix test              # Run all tests
mix test test/phoenix_kit_entities_test.exs  # Run specific test file
mix test --exclude integration  # Run only unit tests (no DB)
mix format            # Format code (imports Phoenix LiveView rules)
mix credo             # Static analysis / linting
mix dialyzer          # Type checking
mix docs              # Generate documentation
```

## Architecture

This is a **library** (not a standalone Phoenix app). It depends on `phoenix_kit` which provides the Module behaviour, Settings API, Auth, shared web components, and admin layout.

### Key Modules

- **`PhoenixKitEntities`** (`lib/phoenix_kit_entities.ex`) — Main module: Ecto schema for entity definitions + `PhoenixKit.Module` behaviour callbacks. This is both the schema and the entry point.

- **`PhoenixKitEntities.EntityData`** (`lib/phoenix_kit_entities/entity_data.ex`) — Ecto schema and CRUD for data records (instances of entity definitions).

- **`PhoenixKitEntities.FieldTypes`** (`lib/phoenix_kit_entities/field_types.ex`) — Registry of 12 supported field types with validation and helper functions.

- **`PhoenixKitEntities.FormBuilder`** (`lib/phoenix_kit_entities/form_builder.ex`) — Dynamic form generation from entity field definitions + data validation.

- **`PhoenixKitEntities.Events`** (`lib/phoenix_kit_entities/events.ex`) — PubSub helpers for entity/data lifecycle events and collaborative editing.

- **`PhoenixKitEntities.Routes`** (`lib/phoenix_kit_entities/routes.ex`) — Admin LiveView routes + public form submission endpoint. Registered via `route_module/0` callback.

- **`PhoenixKitEntities.Web.*`** (`lib/phoenix_kit_entities/web/`) — Admin LiveViews for entity management. PhoenixKit wraps these in the admin layout automatically.

### How It Works

1. Parent app adds this as a dependency in `mix.exs`
2. PhoenixKit scans `.beam` files at startup and auto-discovers modules (zero config)
3. `route_module/0` returns `PhoenixKitEntities.Routes` which defines all admin LiveView routes via `admin_routes/0` / `admin_locale_routes/0`, plus public form routes via `generate/1`
4. Settings are persisted via `PhoenixKit.Settings` API (DB-backed in parent app)
5. Permissions are declared via `permission_metadata/0` and checked via `Scope.has_module_access?/2`
6. `css_sources/0` returns `[:phoenix_kit_entities]` so the installer adds Tailwind @source directives

### Two-Table Database Design

- `phoenix_kit_entities` — Entity definitions (blueprints) with JSONB `fields_definition`
- `phoenix_kit_entity_data` — Data records (instances) with JSONB `data` field values
- Both use UUIDv7 primary keys
- Migration in `PhoenixKitEntities.Migrations.V1` uses `IF NOT EXISTS` for idempotency

## Critical Conventions

- **Module key** must be consistent across all callbacks: `"entities"`
- **Tab IDs**: prefixed with `:admin_` (e.g., `:admin_entities`)
- **URL paths**: use hyphens, not underscores (e.g., `"entities"`)
- **Navigation paths**: always use `PhoenixKit.Utils.Routes.path/1`, never relative paths
- **`enabled?/0`**: must rescue errors and return `false` as fallback (DB may not be available)
- **`enable_system/0` and `disable_system/0`**: use `module_key()` not hardcoded strings
- **LiveViews use `PhoenixKitWeb` macros** — `use PhoenixKitWeb, :live_view` and `use PhoenixKitWeb, :controller` are correct since this module depends on `phoenix_kit` which provides them
- **Don't wrap admin LiveViews with LayoutWrapper** — PhoenixKit auto-applies admin layout for external plugin views via on_mount hook. Wrapping causes double sidebars.
- **LiveView assigns** available in admin pages: `@phoenix_kit_current_scope`, `@current_locale`, `@url_path`
- **Entity names** must be snake_case, start with letter, 2-50 chars: `^[a-z][a-z0-9_]*$`
- **Field definitions** require string keys: `%{"type" => "text", "key" => "name", "label" => "Name"}`
- **Inline templates** — All LiveView templates use inline `~H` sigils (no separate .heex files) for reliable Tailwind CSS scanning

## Routing

This module has multiple admin pages, so it uses the **route module pattern** (not the simple `live_view:` field on `admin_tabs/0`). All admin LiveView routes are defined in `PhoenixKitEntities.Routes`:

- `admin_locale_routes/0` — localized admin routes (with `:locale` prefix)
- `admin_routes/0` — non-localized admin routes
- `generate/1` — public form submission route

The `admin_tabs/0` callback does NOT have a `live_view:` field — the route module handles all routing.

## Tailwind CSS Scanning

This module implements `css_sources/0` returning `[:phoenix_kit_entities]`. PhoenixKit's installer (`mix phoenix_kit.install`) discovers this and adds `@source` directives to the parent's `app.css`. Without this, Tailwind purges CSS classes from our templates.

## External Dependencies (from phoenix_kit)

These are **not our modules** — they come from the `phoenix_kit` dependency:
- `PhoenixKit.Modules.Languages` — language system integration
- `PhoenixKit.Modules.Sitemap.*` — sitemap behaviour/types
- `PhoenixKit.Utils.Multilang` — multi-language JSONB helpers (moved to phoenix_kit core)
- `PhoenixKit.Utils.HtmlSanitizer` — XSS prevention (moved to phoenix_kit core)
- `PhoenixKitWeb.*` — web components, Gettext, layout, icons
- `PhoenixKit.Settings`, `PhoenixKit.Dashboard.Tab`, `PhoenixKit.Users.Auth.*` — core APIs

## Versioning & Releases

### Tagging & GitHub releases

Tags use **bare version numbers** (no `v` prefix):

```bash
git tag 0.1.0
git push origin 0.1.0
```

GitHub releases are created with `gh release create` using the tag as the release name. The title format is `<version> - <date>`, and the body comes from the corresponding `CHANGELOG.md` section:

```bash
gh release create 0.1.0 \
  --title "0.1.0 - 2026-03-24" \
  --notes "$(changelog body for this version)"
```

### Full release checklist

1. Update version in `mix.exs`, `lib/phoenix_kit_entities.ex` (`version/0`), and the version test
2. Add changelog entry in `CHANGELOG.md`
3. Run `mix precommit` — ensure zero warnings/errors before proceeding
4. Commit all changes: `"Bump version to x.y.z"`
5. Push to main and **verify the push succeeded** before tagging
6. Create and push git tag: `git tag x.y.z && git push origin x.y.z`
7. Create GitHub release: `gh release create x.y.z --title "x.y.z - YYYY-MM-DD" --notes "..."`

**IMPORTANT:** Never tag or create a release before all changes are committed and pushed. Tags are immutable pointers — tagging before pushing means the release points to the wrong commit.

## Pull Requests

### Commit Message Rules

Start with action verbs: `Add`, `Update`, `Fix`, `Remove`, `Merge`.

### PR Reviews

PR review files go in `dev_docs/pull_requests/{year}/{pr_number}-{slug}/` directory. Use `{AGENT}_REVIEW.md` naming (e.g., `CLAUDE_REVIEW.md`, `GEMINI_REVIEW.md`). See `dev_docs/pull_requests/README.md`.

## Testing

- Unit tests run without a database (changesets, field types, events, validation)
- Integration tests tagged `:integration` require PostgreSQL: `createdb phoenix_kit_entities_test`
- Test helper auto-detects database availability and excludes integration tests if unavailable

## Installation Note

Host apps must register the route module explicitly in config due to compile-time ordering (the router may compile before this dep is discovered):

```elixir
# config/config.exs
config :phoenix_kit,
  route_modules: [PhoenixKitEntities.Routes]
```

Without this, admin routes (`/admin/entities`, `/admin/settings/entities`, etc.) will return `NoRouteError`.

## External Dependencies

- **PhoenixKit** (`~> 1.7`) — Module behaviour, Settings API, shared components, RepoHelper
- **Phoenix LiveView** (`~> 1.0`) — Admin LiveViews
