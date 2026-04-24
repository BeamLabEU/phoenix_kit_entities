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
- Admin LiveViews (`Web.Entities`, `Web.DataNavigator`, `Web.DataForm`, `Web.DataView`) now thread the current locale through entity lookups so translated `display_name` / `display_name_plural` / `description` render in the admin UI
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
- Add admin LiveViews: Entities, EntityForm, DataNavigator, DataForm, DataView, EntitiesSettings
- Add route module with `admin_routes/0`, `admin_locale_routes/0`, and public form routes
- Add `css_sources/0` for Tailwind CSS scanning support
- Add migration module (v1) with `IF NOT EXISTS` for both tables (run by parent app)
- Add public form component with honeypot, time-based validation, and rate limiting
- Add sitemap integration for published entity data
- Add filesystem mirroring (export/import) with mix tasks
- Add multi-language support (auto-enabled with 2+ languages)
- Add behaviour compliance test suite
- Add unit tests for changesets, field types, events, form validation, HTML sanitization, multilang
