# Follow-up: PR #28 — Per-module gettext i18n

Triaged 2026-08-19 (quality-sweep Phase 1).

## Fixed (pre-existing)

- ~~HIGH: `files:` omitted `priv` from the Hex tarball~~ — `mix.exs` ships `priv`.
- ~~HIGH: backend switch completeness~~ — all 15 gettext-calling files carry `use Gettext, backend: PhoenixKitEntities.Gettext`; zero stragglers on core's backend.
- ~~MEDIUM: `for_picker/0` sorted by translated label (locale-dependent order)~~ — `field_types.ex:500–507` sorts by `category_list/0` index.
- ~~MEDIUM: `label_for/1` literal-clause extraction~~ — 13 literal clauses (now 15: image/video added by the 2026-08-19 sweep after the media rework fell into the exact raw-map trap this review documented).
- ~~MEDIUM: dialyzer `call_without_opaque` gate~~ — `.dialyzer_ignore.exs` wired via `mix.exs`.
- ~~MEDIUM: `version/0` misreporting~~ — compile-time `Mix.Project.config()[:version]`, pinned by test.
- ~~LOW: plural handling~~ — 7 plural msgids per locale, `msgstr[2]` in ru.

## Fixed (quality sweep — 2026-08-19)

- ~~MEDIUM: catalogue integrity drift — `en` had accumulated 9 empty `msgstr` unguarded by the suite~~ — 8 filled (media-field strings from the FieldInput rework), 1 removed (`"Kinnitan"` — a moduledoc example the hand-backfill over-collected; never an extractable call site). `gettext_catalogue_test.exs` now also pins **no empty msgstr** and **msgstr-bindings ⊆ msgid-bindings** per locale, so this class fails loudly instead of shipping.

## Skipped (with rationale)

- Soft: converting sibling packages' hardcoded `version/0` — outside this repo.

## Open

- Soft: the per-module-i18n retrofit guide (backend module + `files:` `priv` entry + dialyzer skip as one checklist) was never written; two independent retrofits missed the dialyzer step identically. Belongs in the main workspace's dev_docs, not this repo — surfaced to Max in the 2026-08-19 sweep report.
