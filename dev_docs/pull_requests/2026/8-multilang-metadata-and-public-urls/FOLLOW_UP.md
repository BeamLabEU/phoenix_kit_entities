# Follow-up Items for PR #8

Triaged against `main` on 2026-04-25. CLAUDE_REVIEW raised 6 findings
(numbered #1–#6 below) plus 5 recommended follow-ups. All six findings
were confirmed still-live; all six are fixed in this batch. Of the five
recommended follow-ups, four are equivalent to the same six findings;
the remaining one (hreflang/canonical helper for SEO) ships here as
well so production multilang sites have a way to declare the
duplication that `public_path/3` produces.

## Fixed (Batch 1 — 2026-04-25)

- ~~**#1** DB query in `mount/3`~~ — `Web.Entities.mount/3` and
  `Web.DataNavigator.mount/3` both called `Entities.list_entities(lang: locale)`
  inline. Mount runs twice (HTTP + WebSocket), so every page load issued
  the query twice. Moved the call into `handle_params/3` (which only
  fires once per page load) and set `entities: []` in mount as a default.
  Both LiveViews share the same locale-aware query through
  `socket.assigns.current_locale`.
- ~~**#2** Bare `rescue _ ->` in `UrlResolver`~~ —
  `safe_get_setting/1`, `safe_get_setting/2`, `safe_get_boolean_setting/2`,
  and `primary_language_base?/1` swallowed *any* exception. Narrowed
  each to `[DBConnection.ConnectionError, Postgrex.Error, Ecto.QueryError, RuntimeError, ArgumentError]`
  with a `Logger.debug` line that includes the message — so real bugs
  (`KeyError`, `FunctionClauseError`, etc.) surface, while the actual
  defensive cases (DB unavailable in tests, Settings table missing,
  repo not started — which Ecto raises as `RuntimeError`) still fall
  through the URL-resolution chain. Kept the original behaviour
  (return `nil` / `default` / `false`) intact.
- ~~**#3** Locale key-match brittleness in `resolve_summary_language/2`~~ —
  `phoenix_kit_entities.ex`. Translations are stored under whatever key
  `set_entity_translation/3` saw (typically the dialect form, e.g.
  `"es-ES"`), but callers may query with either dialect or base codes.
  Without normalization the dialect/base mismatch silently missed and
  the sidebar fell back to primary-language labels. Replaced the inline
  `get_in(summary, [:settings, "translations", lang_code])` with a new
  `lookup_translation/2` helper that:
  1. Tries the exact key (`"es-ES"` → `"es-ES"`).
  2. On miss, normalizes via `DialectMapper.extract_base/1` and finds
     any translation key whose base matches the queried base —
     deterministic via sort.

  Same helper is now also used by `get_entity_translation/2`, so the
  struct path and the summary path resolve identically.
- ~~**#4** Catchall regex was permissive~~ — `url_resolver.ex:103-107`.
  `^/:[a-z_]+/:[a-z_]+$` would have classified *any* two-segment
  parameterized route as the entity catchall (`/:category/:item`,
  `/:owner/:repo`, etc.) and rewritten every entity onto it via
  `public_path/3`. Tightened to `^/:[a-z_]+/:(slug|id)$` so only
  routes whose second segment is `:slug` or `:id` are picked up as the
  entity catchall.
- ~~**#5** Translated-slug fallback produces duplicate URLs across
  locales~~ — net-new `EntityData.public_alternates/3` ships alongside
  `public_path/3` and `public_url/3`. Returns
  `%{canonical: ..., alternates: [%{locale: "en", href: ...}, ...,
  %{locale: "x-default", href: ...}]}` driven by
  `Multilang.enabled_languages/0` and `Multilang.primary_language/0`,
  with rescue fallback when Multilang is unavailable. Locale codes are
  emitted as base codes (`"en"`, `"es"`) per Google's hreflang docs.
  Production multilang sites can now emit
  `<link rel="alternate" hreflang="..." />` and
  `<link rel="canonical" />` to declare the duplication that
  `public_path/3` produces with secondary-language locales.
- ~~**#6** `@derive Jason.Encoder` on `EntityData` drops `entity_uuid`~~ —
  added `:entity_uuid` to the `only:` list so JSON consumers can see
  the FK without a manual override.

## Files touched

| File | Change |
|------|--------|
| `lib/phoenix_kit_entities.ex` | #3 `lookup_translation/2` + `safe_extract_base/1` helpers; `resolve_summary_language/2` and `get_entity_translation/2` use them; new `DialectMapper` alias |
| `lib/phoenix_kit_entities/url_resolver.ex` | #2 narrowed rescues + Logger.debug; #4 tightened catchall regex to `:slug`/`:id`; new `require Logger` |
| `lib/phoenix_kit_entities/entity_data.ex` | #5 `public_alternates/3` + private `enabled_locales/0`, `safe_primary_language/1`, `locale_base/1`; #6 added `:entity_uuid` to Jason encoder; new `DialectMapper` alias |
| `lib/phoenix_kit_entities/web/entities.ex` | #1 deferred `list_entities/1` from mount/3 to handle_params/3 |
| `lib/phoenix_kit_entities/web/data_navigator.ex` | #1 deferred `list_entities/1` from mount/3 to handle_params/3 |

## Verification

- `mix format --check-formatted` ✓
- `mix compile --warnings-as-errors` ✓
- `mix credo --strict` — no issues
- `mix dialyzer` — 0 errors
- `mix test` — 320 tests, 59 failures — same as `main` baseline (the
  59 pre-existing failures are changeset tests that hit the Repo
  without one; addressed by Phase 2 C7 test infra work)

Pinning tests for the six findings + the new helper land in the Phase 2
sweep (C8 / C10 / C11). They are intentionally NOT bundled here so the
PR-followup commit stays narrow.

## Open

None.
