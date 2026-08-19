# Follow-up: PR #26 — Projects data-tab slugs

Triaged 2026-08-19 (quality-sweep Phase 1).

## Fixed (pre-existing)

- ~~HIGH: reviewer stripped `locale:` from `Slug.slugify/2` against a stale core~~ — reverted in 0.3.1; both sites restored (`data_form.ex:1067`, `:1249` carry `locale:` + `transliterate: true`) and survived through 0.4.0.
- ~~HIGH: `lang` threading through `auto_generate_entity_slug/4`~~ — arity-4 with all three call sites passing it (`data_form.ex:402/408/1083`).
- ~~MEDIUM: unused `\\ nil` default rejected by `--warnings-as-errors`~~ — gone from both clause heads.
- ~~MEDIUM: the `transliterate: true` additions~~ — present at all four sites; redundancy under core 2.0 is documented in-code (`data_form.ex:1061–1063`).

## Skipped (with rationale)

- N/A: the review's notes about `phoenix_kit_posts` comments — different repo, corrected there in posts 0.2.1.

## Open

- Observation (not a review finding): `entity_form.ex:1508` still calls `Slug.slugify(name, separator: "_", transliterate: true)` with no `locale:`. That is the field-KEY slug — a machine identifier where locale-independence is arguably correct — but it is the one `slugify` site the correction pass did not touch. Decide deliberately rather than by omission.
