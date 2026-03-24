# PhoenixKitEntities

Dynamic content types for PhoenixKit. Define custom entities (like "Product", "Team Member", "FAQ") with flexible field schemas — no database migrations needed per entity.

## Table of Contents

- [What this provides](#what-this-provides)
- [Quick start](#quick-start)
- [Dependency types](#dependency-types)
- [Project structure](#project-structure)
- [Entity definitions](#entity-definitions)
- [Entity data records](#entity-data-records)
- [Field types](#field-types)
- [Admin UI](#admin-ui)
- [Multi-language support](#multi-language-support)
- [Public forms](#public-forms)
- [Filesystem mirroring](#filesystem-mirroring)
- [Events & PubSub](#events--pubsub)
- [Available callbacks](#available-callbacks)
- [Mix tasks](#mix-tasks)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

## What this provides

- Dynamic entity definitions with JSONB field schemas (no migrations per entity)
- 12 field types: text, textarea, email, url, rich_text, number, boolean, date, select, radio, checkbox, file
- Complete admin UI (LiveView) for managing entity definitions and data records
- Multi-language support (auto-enabled when 2+ languages are active)
- Collaborative editing with FIFO locking and presence tracking
- Public form builder with honeypot, time-based validation, and rate limiting
- Filesystem mirroring for export/import of entity definitions and data
- PubSub events for real-time updates across admin sessions
- Sitemap integration for published entity data
- Zero-config auto-discovery — just add the dependency

## Quick start

Add to your parent app's `mix.exs`:

```elixir
{:phoenix_kit_entities, path: "../phoenix_kit_entities"}
```

Run `mix deps.get` and start the server. The module appears in:

- **Admin sidebar** (under Modules section) — browse entities and their data
- **Admin > Modules** — toggle it on/off
- **Admin > Roles** — grant/revoke access per role
- **Admin > Settings > Entities** — configure module settings

Enable the system:

```elixir
PhoenixKitEntities.enable_system()
```

Create your first entity:

```elixir
{:ok, entity} = PhoenixKitEntities.create_entity(%{
  name: "product",
  display_name: "Product",
  display_name_plural: "Products",
  icon: "hero-cube",
  created_by_uuid: admin_user.uuid,
  fields_definition: [
    %{"type" => "text", "key" => "name", "label" => "Name", "required" => true},
    %{"type" => "number", "key" => "price", "label" => "Price"},
    %{"type" => "textarea", "key" => "description", "label" => "Description"},
    %{"type" => "select", "key" => "category", "label" => "Category",
      "options" => ["Electronics", "Clothing", "Food"]}
  ]
})
```

Create data records:

```elixir
{:ok, record} = PhoenixKitEntities.EntityData.create(%{
  entity_uuid: entity.uuid,
  title: "iPhone 15",
  status: "published",
  created_by_uuid: admin_user.uuid,
  data: %{
    "name" => "iPhone 15",
    "price" => 999,
    "description" => "Latest iPhone model",
    "category" => "Electronics"
  }
})
```

## Dependency types

### Local development (`path:`)

```elixir
{:phoenix_kit_entities, path: "../phoenix_kit_entities"}
```

Changes to the module's source are picked up automatically on recompile.

### Git dependency (`git:`)

```elixir
{:phoenix_kit_entities, git: "https://github.com/mdon/phoenix_kit_entities.git"}
```

After updating the remote: `mix deps.update phoenix_kit_entities`, then `mix deps.compile phoenix_kit_entities --force` + restart the server.

### Hex package

```elixir
{:phoenix_kit_entities, "~> 0.1.0"}
```

## Project structure

```
lib/
  phoenix_kit_entities.ex              # Main module (schema + PhoenixKit.Module behaviour)
  phoenix_kit_entities/
    entity_data.ex                     # Data record schema and CRUD
    field_type.ex                      # Field type struct
    field_types.ex                     # Field type registry (12 types)
    form_builder.ex                    # Dynamic form generation + validation
    events.ex                          # PubSub broadcast/subscribe
    presence.ex                        # Phoenix.Presence for editing
    presence_helpers.ex                # FIFO locking, session tracking
    routes.ex                          # Admin + public route definitions
    sitemap_source.ex                  # Sitemap integration
    components/
      entity_form.ex                   # Embeddable public form component
    controllers/
      entity_form_controller.ex        # Public form submission handler
    migrations/
      v1.ex                            # Consolidated IF NOT EXISTS migration
    mirror/
      exporter.ex                      # Entity/data export to JSON
      importer.ex                      # Entity/data import from JSON
      storage.ex                       # File storage for mirror
    mix_tasks/
      export.ex                        # mix phoenix_kit_entities.export
      import.ex                        # mix phoenix_kit_entities.import
    web/
      entities.ex                      # Entity list LiveView (inline template)
      entity_form.ex                   # Entity definition builder LiveView
      data_navigator.ex                # Data record browser LiveView
      data_form.ex                     # Data record form LiveView
      data_view.ex                     # Data record read-only view
      entities_settings.ex             # Module settings LiveView
      hooks.ex                         # Shared LiveView hooks
```

## Entity definitions

Entity definitions are blueprints for custom content types. Each entity has a name, display names, and a JSONB array of field definitions.

```elixir
# List all entities
PhoenixKitEntities.list_entities()

# Get by name
PhoenixKitEntities.get_entity_by_name("product")

# Create
{:ok, entity} = PhoenixKitEntities.create_entity(%{...})

# Update
{:ok, entity} = PhoenixKitEntities.update_entity(entity, %{status: "published"})

# Delete (cascades to all data records)
{:ok, entity} = PhoenixKitEntities.delete_entity(entity)
```

### Name constraints

- Must be unique, snake_case, 2-50 characters
- Format: `^[a-z][a-z0-9_]*$`
- Examples: `product`, `team_member`, `faq_item`

### Status workflow

Entities support three statuses: `draft`, `published`, `archived`.

## Entity data records

Data records are instances of an entity definition. Field values are stored in a JSONB `data` column.

```elixir
alias PhoenixKitEntities.EntityData

# List records for an entity
EntityData.list_by_entity(entity.uuid)

# Filter by status
EntityData.list_by_entity_and_status(entity.uuid, "published")

# Search by title
EntityData.search_by_title("iPhone", entity.uuid)

# Get by slug
EntityData.get_by_slug(entity.uuid, "iphone-15")

# CRUD
{:ok, record} = EntityData.create(%{...})
{:ok, record} = EntityData.update(record, %{...})
{:ok, record} = EntityData.delete(record)
```

### Manual ordering

Entities can use auto sort (by creation date) or manual sort (by position). Configure via the entity's `settings`:

```elixir
PhoenixKitEntities.update_sort_mode(entity, "manual")
```

## Field types

| Category | Types | Notes |
|----------|-------|-------|
| Basic | `text`, `textarea`, `email`, `url`, `rich_text` | Rich text is HTML-sanitized |
| Numeric | `number` | Accepts integers and floats |
| Boolean | `boolean` | Toggle/checkbox |
| Date | `date` | Date picker |
| Choice | `select`, `radio`, `checkbox` | Require `options` array |
| Media | `file`, `image` | Coming soon |
| Relations | `relation` | Coming soon |

Each field definition is a map with:

```elixir
%{
  "type" => "text",          # Required
  "key" => "title",          # Required, unique per entity
  "label" => "Title",        # Required
  "required" => true,        # Optional, default false
  "default" => "",           # Optional
  "options" => ["A", "B"],   # Required for select/radio/checkbox
  "validation" => %{...}     # Optional validation rules
}
```

Use the helper functions:

```elixir
alias PhoenixKitEntities.FieldTypes

FieldTypes.text_field("name", "Full Name", required: true)
FieldTypes.select_field("category", "Category", ["Tech", "Business"])
FieldTypes.boolean_field("featured", "Featured", default: true)
```

## Admin UI

Admin routes are registered via `PhoenixKitEntities.Routes` (returned by `route_module/0`):

| Route | LiveView | Purpose |
|-------|----------|---------|
| `/admin/entities` | `Web.Entities` | List all entity definitions |
| `/admin/entities/new` | `Web.EntityForm` | Create entity definition |
| `/admin/entities/:id/edit` | `Web.EntityForm` | Edit entity definition |
| `/admin/entities/:name/data` | `Web.DataNavigator` | Browse entity records |
| `/admin/entities/:name/data/new` | `Web.DataForm` | Create record |
| `/admin/entities/:name/data/:uuid` | `Web.DataForm` | Edit record |
| `/admin/settings/entities` | `Web.EntitiesSettings` | Module settings |

## Multi-language support

Multilang is auto-enabled when PhoenixKit has 2+ languages configured. Data is stored in a nested JSONB structure:

```elixir
# Multilang data format
%{
  "en" => %{"title" => "Hello", "description" => "..."},
  "es" => %{"title" => "Hola", "description" => "..."}
}
```

See `PhoenixKit.Utils.Multilang` for helper functions.

## Public forms

Entities can expose public submission forms. Enable in entity settings, then embed:

```html
<EntityForm entity_slug="contact" />
```

Or use the controller endpoint. Public forms include:
- Honeypot field for bot detection
- Time-based validation (minimum 3 seconds)
- Rate limiting (5 submissions per 60 seconds)
- Browser/OS/device metadata capture

## Filesystem mirroring

Export and import entity definitions and data as JSON files:

```bash
mix phoenix_kit_entities.export
mix phoenix_kit_entities.import
```

Or programmatically:

```elixir
PhoenixKitEntities.Mirror.Exporter.export_all(path)
PhoenixKitEntities.Mirror.Importer.import_all(path)
```

## Events & PubSub

Subscribe to real-time events:

```elixir
alias PhoenixKitEntities.Events

# Entity lifecycle
Events.subscribe_to_entities()
# Receives: {:entity_created, uuid}, {:entity_updated, uuid}, {:entity_deleted, uuid}

# Data lifecycle (all entities)
Events.subscribe_to_all_data()
# Receives: {:data_created, entity_uuid, data_uuid}, etc.

# Data lifecycle (specific entity)
Events.subscribe_to_entity_data(entity_uuid)
```

## Available callbacks

This module implements `PhoenixKit.Module` with these callbacks:

| Callback | Value |
|----------|-------|
| `module_key/0` | `"entities"` |
| `module_name/0` | `"Entities"` |
| `enabled?/0` | Reads `entities_enabled` setting |
| `enable_system/0` | Sets `entities_enabled` to true |
| `disable_system/0` | Sets `entities_enabled` to false |
| `permission_metadata/0` | Icon: `hero-cube-transparent` |
| `admin_tabs/0` | Entities tab with dynamic entity children |
| `settings_tabs/0` | Settings tab under admin settings |
| `children/0` | `[PhoenixKitEntities.Presence]` |
| `css_sources/0` | `[:phoenix_kit_entities]` |
| `route_module/0` | `PhoenixKitEntities.Routes` |
| `get_config/0` | Returns enabled status, limits, stats |

## Mix tasks

```bash
# Export all entities and data to JSON
mix phoenix_kit_entities.export

# Import entities and data from JSON
mix phoenix_kit_entities.import
```

## Database

The migration lives in PhoenixKit core. This module also provides a consolidated migration at `PhoenixKitEntities.Migrations.V1` with `IF NOT EXISTS` logic, safe to run standalone:

```elixir
# Two tables:
# phoenix_kit_entities       — entity definitions (blueprints)
# phoenix_kit_entity_data    — data records (instances)
# Both use UUIDv7 primary keys
```

## Testing

```bash
# Create test database
createdb phoenix_kit_entities_test

# Run all tests
mix test

# Run only unit tests (no DB needed)
mix test --exclude integration
```

## Troubleshooting

### Module not appearing in admin

1. Verify the dependency is in `mix.exs` and `mix deps.get` was run
2. Check `PhoenixKitEntities.enabled?()` returns `true`
3. Run `PhoenixKitEntities.enable_system()` if needed

### "entities_enabled" setting not found

The settings are seeded by the migration. If using PhoenixKit core migrations, they're created by V17. If standalone, run the `PhoenixKitEntities.Migrations.V1` migration.

### Entity name validation fails

Names must be snake_case, start with a letter, 2-50 characters. Examples: `product`, `team_member`, `faq_item`. Invalid: `Product`, `123abc`, `a`.

### Changes not taking effect after editing

Force a clean rebuild: `mix deps.clean phoenix_kit_entities && mix deps.get && mix deps.compile phoenix_kit_entities --force && mix compile --force`
