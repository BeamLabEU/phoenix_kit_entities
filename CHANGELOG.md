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
