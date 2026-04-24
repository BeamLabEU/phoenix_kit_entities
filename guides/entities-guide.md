# PhoenixKit Entities Guide

**Dynamic content types without database migrations.**

The Entities system lets you create custom content types (like blog posts, products, forms) programmatically with flexible field schemas. No migrations required.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Enable the System](#enable-the-system)
3. [Creating Entities](#creating-entities)
4. [Field Types](#field-types)
5. [Field Builder Helpers](#field-builder-helpers)
6. [Managing Data Records](#managing-data-records)
7. [Public Forms](#public-forms)
8. [API Reference](#api-reference)
9. [Common Patterns](#common-patterns)
10. [Multi-Language Support](#multi-language-support)
11. [Public URL Resolution](#public-url-resolution)

---

## Quick Start

```elixir
# 1. Enable the Entities system
PhoenixKitEntities.enable_system()

# 2. Create an entity
alias PhoenixKitEntities
alias PhoenixKitEntities.FieldTypes

{:ok, entity} = Entities.create_entity(%{
  name: "contact_form",
  display_name: "Contact Form",
  status: "published",
  fields_definition: [
    FieldTypes.text_field("name", "Name", required: true),
    FieldTypes.email_field("email", "Email", required: true),
    FieldTypes.textarea_field("message", "Message", required: true)
  ]
})

# 3. Create data records
{:ok, record} = PhoenixKitEntities.EntityData.create(%{
  entity_uuid: entity.uuid,
  title: "New Submission",
  status: "published",
  data: %{
    "name" => "John Doe",
    "email" => "john@example.com",
    "message" => "Hello!"
  }
})
```

---

## Enable the System

### Via Code

```elixir
PhoenixKitEntities.enable_system()
```

### Via Admin UI

Visit `/phoenix_kit/admin/modules` and enable the Entities module.

---

## Creating Entities

### Basic Entity

```elixir
{:ok, entity} = PhoenixKitEntities.create_entity(%{
  name: "article",
  display_name: "Article",
  display_name_plural: "Articles",
  description: "Blog articles and posts",
  icon: "hero-document-text",
  status: "published",
  created_by_uuid: admin_user.uuid,
  fields_definition: [
    %{"type" => "text", "key" => "title", "label" => "Title", "required" => true},
    %{"type" => "rich_text", "key" => "content", "label" => "Content"},
    %{"type" => "select", "key" => "status", "label" => "Status",
      "options" => ["Draft", "Published", "Archived"]}
  ]
})
```

### Entity with Auto-filled Creator

```elixir
# Note: created_by_uuid is optional - it auto-fills with first admin user if not provided
{:ok, entity} = PhoenixKitEntities.create_entity(%{
  name: "product",
  display_name: "Product",
  status: "published",
  # created_by_uuid: admin.uuid,  # Optional! Auto-filled if omitted
  fields_definition: [
    FieldTypes.text_field("name", "Name", required: true),
    FieldTypes.number_field("price", "Price"),
    FieldTypes.textarea_field("description", "Description")
  ]
})
```

### Getting Admin User for created_by_uuid

If you need to explicitly set `created_by_uuid`, use these helpers:

```elixir
# Get first admin (Owner or Admin role) - recommended
admin_uuid = PhoenixKit.Users.Auth.get_first_admin_uuid()

# Get first user (any role)
user_uuid = PhoenixKit.Users.Auth.get_first_user_uuid()

# Get full user struct if needed
admin = PhoenixKit.Users.Auth.get_first_admin()
```

**Note:** `created_by_uuid` is now auto-filled for both `Entities.create_entity/1` and `EntityData.create/1` if not provided. It uses the first admin, or falls back to the first user.

---

## Field Types

### Available Field Types

| Type | Description | Requires Options | Status |
|------|-------------|------------------|--------|
| `text` | Single-line text | No | ✅ |
| `textarea` | Multi-line text | No | ✅ |
| `email` | Email with validation | No | ✅ |
| `url` | URL with validation | No | ✅ |
| `number` | Numeric input | No | ✅ |
| `boolean` | True/false toggle | No | ✅ |
| `date` | Date picker | No | ✅ |
| `rich_text` | WYSIWYG editor | No | ✅ |
| `select` | Dropdown | Yes | ✅ |
| `radio` | Radio buttons | Yes | ✅ |
| `checkbox` | Multiple checkboxes | Yes | ✅ |
| `file` | File upload | No | ✅ |
| `image` | Image upload | No | 🚧 Coming soon |
| `relation` | Link to other entity | Yes | 🚧 Coming soon |

> **Note**: `image` and `relation` fields render "Coming Soon" placeholders in forms. The `file` field type is fully implemented.

### Raw Field Definition

```elixir
%{
  "type" => "text",
  "key" => "name",
  "label" => "Full Name",
  "required" => true,
  "default" => nil,
  "validation" => %{},
  "options" => []
}
```

---

## Field Builder Helpers

Use these helpers to create field definitions more easily:

```elixir
alias PhoenixKitEntities.FieldTypes

# Text fields
FieldTypes.text_field("name", "Full Name", required: true)
FieldTypes.textarea_field("bio", "Biography")
FieldTypes.email_field("email", "Email Address", required: true)
FieldTypes.url_field("website", "Website")
FieldTypes.rich_text_field("content", "Content")

# Numeric and boolean
FieldTypes.number_field("age", "Age")
FieldTypes.boolean_field("active", "Is Active", default: true)

# Date field
FieldTypes.date_field("published_on", "Published On")

# File upload
FieldTypes.file_field("attachment", "Attachment")
FieldTypes.file_field("documents", "Documents",
  max_entries: 5,
  max_file_size: 10_485_760,  # 10MB
  accept: [".pdf", ".doc", ".docx"]
)

# Choice fields with options
FieldTypes.select_field("category", "Category", ["Tech", "Business", "Other"])
FieldTypes.radio_field("priority", "Priority", ["Low", "Medium", "High"], required: true)
FieldTypes.checkbox_field("tags", "Tags", ["Featured", "Popular", "New"])

# Generic with options
FieldTypes.new_field("select", "status", "Status", options: ["Active", "Inactive"], required: true)
```

### Creating Entity with Choice Fields

```elixir
alias PhoenixKitEntities
alias PhoenixKitEntities.FieldTypes

{:ok, entity} = Entities.create_entity(%{
  name: "survey_response",
  display_name: "Survey Response",
  status: "published",
  fields_definition: [
    FieldTypes.text_field("name", "Name", required: true),
    FieldTypes.email_field("email", "Email", required: true),
    FieldTypes.select_field("subject", "Subject", [
      "General Inquiry",
      "Support",
      "Sales",
      "Partnership"
    ], required: true),
    FieldTypes.textarea_field("message", "Message", required: true),
    FieldTypes.checkbox_field("interests", "Interests", [
      "Product Updates",
      "Newsletter",
      "Events"
    ])
  ]
})
```

---

## Managing Data Records

### Create a Data Record

```elixir
{:ok, record} = PhoenixKitEntities.EntityData.create(%{
  entity_uuid: entity.uuid,
  title: "New Contact",
  status: "published",
  created_by_uuid: user.uuid,
  data: %{
    "name" => "John Doe",
    "email" => "john@example.com",
    "message" => "Hello!"
  }
})
```

### Query Records

```elixir
# All records for an entity
records = PhoenixKitEntities.EntityData.list_by_entity(entity.uuid)

# Search by title (search_term first, entity_uuid optional second)
results = PhoenixKitEntities.EntityData.search_by_title("John", entity.uuid)

# Get entity by name
entity = PhoenixKitEntities.get_entity_by_name("contact_form")

# Get by UUID
record = PhoenixKitEntities.EntityData.get(record_uuid)

# Filter by status
records = PhoenixKitEntities.EntityData.list_by_entity_and_status(entity.uuid, "published")

# Get by slug
record = PhoenixKitEntities.EntityData.get_by_slug(entity.uuid, "my-record-slug")
```

### Update and Delete

```elixir
# Update
{:ok, updated} = PhoenixKitEntities.EntityData.update(record, %{
  title: "Updated Title",
  data: Map.put(record.data, "new_field", "value")
})

# Delete
{:ok, deleted} = PhoenixKitEntities.EntityData.delete(record)
```

---

## Public Forms

Embed entity-based forms on public pages for contact forms, surveys, lead capture, etc.

### Enable Public Form for an Entity

```elixir
# Via admin UI: /phoenix_kit/admin/entities/:id/edit
# Or programmatically:
PhoenixKitEntities.update_entity(entity, %{
  settings: %{
    "public_form_enabled" => true,
    "public_form_fields" => ["name", "email", "message"],
    "public_form_title" => "Contact Us",
    "public_form_description" => "We'll get back to you within 24 hours.",
    "public_form_submit_text" => "Send Message",
    "public_form_success_message" => "Thank you! We received your message."
  }
})
```

### Embed in Your Templates

The EntityForm is a function component (not a LiveComponent), so use it directly:

```heex
<%# In .phk publishing pages (recommended) %>
<EntityForm entity_slug="contact_form" />

<%# Or call the render function directly in regular .heex templates %>
<PhoenixKit.Modules.Shared.Components.EntityForm.render
  attributes={%{"entity_slug" => "contact_form"}}
/>
```

> **Note**: Do not use `live_component` - EntityForm uses `Phoenix.Component`, not `Phoenix.LiveComponent`.

### Security Options

Configure in entity settings or admin UI:

| Setting | Default | Description |
|---------|---------|-------------|
| `public_form_honeypot` | false | Hidden field to catch bots |
| `public_form_time_check` | false | Reject submissions < 3 seconds |
| `public_form_rate_limit` | false | 5 submissions/minute per IP |
| `public_form_debug_mode` | false | Show detailed error messages |
| `public_form_collect_metadata` | true | Capture IP, browser, device |

### Security Actions

Each security check can be configured with an action:

| Action | Behavior |
|--------|----------|
| `reject_silent` | Show fake success, don't save |
| `reject_error` | Show error message, don't save |
| `save_suspicious` | Save with "draft" status, flag in metadata |
| `save_log` | Save normally, log warning |

### Form Submission Route

Forms POST to: `POST /phoenix_kit/entities/:entity_slug/submit`

This is handled by `PhoenixKitWeb.EntityFormController`.

---

## API Reference

### PhoenixKitEntities

```elixir
# Check if system is enabled
PhoenixKitEntities.enabled?() :: boolean()

# Enable/disable
PhoenixKitEntities.enable_system() :: {:ok, Setting.t()}
PhoenixKitEntities.disable_system() :: {:ok, Setting.t()}

# Get by ID
PhoenixKitEntities.get_entity(id) :: Entity.t() | nil        # Returns nil if not found
PhoenixKitEntities.get_entity!(id) :: Entity.t()             # Raises if not found
PhoenixKitEntities.get_entity_by_name(name) :: Entity.t() | nil

# List
PhoenixKitEntities.list_entities() :: [Entity.t()]
PhoenixKitEntities.list_active_entities() :: [Entity.t()]    # Only status: "published"

# Create/Update/Delete
PhoenixKitEntities.create_entity(attrs) :: {:ok, Entity.t()} | {:error, Changeset.t()}
PhoenixKitEntities.update_entity(entity, attrs) :: {:ok, Entity.t()} | {:error, Changeset.t()}
PhoenixKitEntities.delete_entity(entity) :: {:ok, Entity.t()} | {:error, Changeset.t()}

# Changeset (for forms)
PhoenixKitEntities.change_entity(entity, attrs \\ %{}) :: Changeset.t()

# Stats
PhoenixKitEntities.get_system_stats() :: %{
  total_entities: integer(),
  active_entities: integer(),
  total_data_records: integer()
}
```

### PhoenixKitEntities.EntityData

```elixir
# Get by ID
EntityData.get(id) :: EntityData.t() | nil           # Returns nil if not found
EntityData.get!(id) :: EntityData.t()                # Raises if not found
EntityData.get_by_slug(entity_uuid, slug) :: EntityData.t() | nil

# List/Query
EntityData.list_all() :: [EntityData.t()]
EntityData.list_by_entity(entity_uuid) :: [EntityData.t()]
EntityData.list_by_entity_and_status(entity_uuid, status) :: [EntityData.t()]
EntityData.search_by_title(search_term, entity_uuid \\ nil) :: [EntityData.t()]

# Create/Update/Delete
EntityData.create(attrs) :: {:ok, EntityData.t()} | {:error, Changeset.t()}
EntityData.update(record, attrs) :: {:ok, EntityData.t()} | {:error, Changeset.t()}
EntityData.delete(record) :: {:ok, EntityData.t()} | {:error, Changeset.t()}

# Changeset (for forms)
EntityData.change(record, attrs \\ %{}) :: Changeset.t()
```

### PhoenixKitEntities.FieldTypes

```elixir
# Field builder helpers (recommended for programmatic entity creation)
FieldTypes.text_field(key, label, opts \\ []) :: map()
FieldTypes.textarea_field(key, label, opts \\ []) :: map()
FieldTypes.email_field(key, label, opts \\ []) :: map()
FieldTypes.url_field(key, label, opts \\ []) :: map()
FieldTypes.number_field(key, label, opts \\ []) :: map()
FieldTypes.boolean_field(key, label, opts \\ []) :: map()
FieldTypes.date_field(key, label, opts \\ []) :: map()
FieldTypes.rich_text_field(key, label, opts \\ []) :: map()
FieldTypes.file_field(key, label, opts \\ []) :: map()

# Choice field helpers (options required)
FieldTypes.select_field(key, label, options, opts \\ []) :: map()
FieldTypes.radio_field(key, label, options, opts \\ []) :: map()
FieldTypes.checkbox_field(key, label, options, opts \\ []) :: map()

# Generic field builder
FieldTypes.new_field(type, key, label, opts \\ []) :: map()
# opts: [required: bool, default: any, options: list]

# Field type info
FieldTypes.all() :: map()
FieldTypes.requires_options?(type) :: boolean()
FieldTypes.validate_field(field_map) :: {:ok, map()} | {:error, String.t()}
```

---

## Common Patterns

### Create a Contact Form Entity

```elixir
# In a migration or seeds.exs
admin = PhoenixKit.Users.Auth.get_user_by_email("admin@example.com")

{:ok, _entity} = PhoenixKitEntities.create_entity(%{
  name: "contact",
  display_name: "Contact Submission",
  status: "published",
  created_by_uuid: admin.uuid,
  fields_definition: [
    %{"type" => "text", "key" => "name", "label" => "Name", "required" => true},
    %{"type" => "email", "key" => "email", "label" => "Email", "required" => true},
    %{"type" => "select", "key" => "subject", "label" => "Subject", "required" => true,
      "options" => ["General Inquiry", "Support", "Sales", "Partnership"]},
    %{"type" => "textarea", "key" => "message", "label" => "Message", "required" => true}
  ],
  settings: %{
    "public_form_enabled" => true,
    "public_form_fields" => ["name", "email", "subject", "message"],
    "public_form_title" => "Contact Us",
    "public_form_honeypot" => true,
    "public_form_time_check" => true,
    "public_form_rate_limit" => true
  }
})
```

### List All Contact Submissions

```elixir
entity = PhoenixKitEntities.get_entity_by_name("contact")
submissions = PhoenixKitEntities.EntityData.list_by_entity(entity.uuid)

for submission <- submissions do
  IO.puts("#{submission.data["name"]} - #{submission.data["email"]}")
end
```

### Export Entity Data

```elixir
entity = PhoenixKitEntities.get_entity_by_name("contact")
records = PhoenixKitEntities.EntityData.list_by_entity(entity.uuid)

# Convert to list of maps
data = Enum.map(records, fn r ->
  Map.merge(r.data, %{
    "uuid" => r.uuid,
    "created_at" => r.date_created,
    "status" => r.status
  })
end)

# Export as JSON
Jason.encode!(data)
```

---

## Multi-Language Support

When PhoenixKit has 2+ languages enabled, entity definitions and data records both support translations.

### Translating Entity Metadata

`display_name`, `display_name_plural`, and `description` are translatable. Translations live in `entity.settings["translations"]` and can be set either through the admin entity form (language tabs appear above the translatable fields) or programmatically:

```elixir
alias PhoenixKitEntities, as: Entities

{:ok, entity} = Entities.set_entity_translation(entity, "es-ES", %{
  "display_name" => "Producto",
  "display_name_plural" => "Productos",
  "description" => "Catálogo de productos"
})

# Read a specific translation (merged with primary fallback)
Entities.get_entity_translation(entity, "es-ES")
# => %{"display_name" => "Producto", "display_name_plural" => "Productos", ...}

# All translations
Entities.get_entity_translations(entity)
# => %{"es-ES" => %{...}, "fr-FR" => %{...}}

# Remove a language
Entities.remove_entity_translation(entity, "es-ES")
```

### Reading Translated Metadata in Consumers

Every query function accepts an optional `lang:` keyword. When supplied, the returned struct has translatable fields resolved to that locale (falling back to primary for missing keys):

```elixir
Entities.list_entities(lang: "es-ES")
Entities.list_active_entities(lang: "es-ES")
Entities.get_entity(uuid, lang: "es-ES")
Entities.get_entity!(uuid, lang: "es-ES")
Entities.get_entity_by_name("product", lang: "es-ES")
Entities.list_entity_summaries(lang: "es-ES")
```

For parent-app listings at `/:locale/...` routes, threading the current locale through `lang:` is the difference between translated and untranslated page titles, breadcrumbs, and `<h1>` content.

### Translating Data Records

Values inside `entity_data.data` use a nested JSONB structure with a primary-language marker:

```elixir
%{
  "_primary_language" => "en-US",
  "en-US" => %{"_title" => "Hello", "body" => "..."},
  "es-ES" => %{"_title" => "Hola"}   # overrides only
}
```

The same `lang:` option works on every `EntityData` query:

```elixir
alias PhoenixKitEntities.EntityData

EntityData.get!(uuid, lang: "es-ES")
EntityData.list_by_entity(entity_uuid, lang: "es-ES")
EntityData.search_by_title("Hola", entity_uuid, lang: "es-ES")
EntityData.published_records(entity_uuid, lang: "es-ES")
EntityData.get_by_slug(entity_uuid, "mi-articulo", lang: "es-ES")
```

---

## Public URL Resolution

Use `EntityData.public_path/3` / `public_url/3` to build locale-aware public links for records. The URL-pattern resolution chain introspects the parent app's router so you don't hand-wire paths per entity.

```elixir
alias PhoenixKitEntities.EntityData

EntityData.public_path(entity, record)
# => "/products/my-item"

EntityData.public_path(entity, record, locale: "es-ES")
# => "/es/products/my-item"   (non-primary locale → base prefix added)

EntityData.public_path(entity, record, locale: "en-US")
# => "/products/my-item"      (primary locale → no prefix)

EntityData.public_url(entity, record, base_url: "https://shop.example.com")
# => "https://shop.example.com/products/my-item"
```

### Pattern resolution chain

1. `entity.settings["sitemap_url_pattern"]` — per-entity override (`"/blog/:slug"`)
2. Router introspection — explicit (`live "/pages/:slug", ...`) or catchall (`/:entity_name/:slug`)
3. Per-entity setting `sitemap_entity_<name>_pattern`
4. Global setting `sitemap_entities_pattern`
5. Fallback `/<entity_name>/:slug`

Placeholders: `:slug` (falls back to UUID when nil) and `:id` (UUID).

### Translated slugs

When a record has a secondary-language slug override stored as `data[locale]["_slug"]`, `public_path/3` substitutes that override for the `:slug` placeholder:

```elixir
record = %{
  slug: "my-item",
  data: %{"es-ES" => %{"_slug" => "mi-articulo"}}
}

EntityData.public_path(entity, record, locale: "es-ES")
# => "/es/products/mi-articulo"
```

### Batch usage

For rendering a listing of records, pre-build the routes cache once:

```elixir
cache = PhoenixKitEntities.UrlResolver.build_routes_cache()

Enum.map(records, fn r ->
  EntityData.public_path(entity, r, locale: locale, routes_cache: cache)
end)
```

---

**Last Updated**: 2026-04-24
