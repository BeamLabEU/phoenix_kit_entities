# PR #26 — Contribute a Data tab to the projects hub, repair the suite, slug records in their own language

**Reviewed:** 2026-08-10 · **Author:** mdon · **Verdict:** merged, **with a fix
applied on `main`.** Released in **0.3.0**.

+296 / −68 across 8 files. Reviewed as part of the phoenix_kit 2.0 sweep.

## Accepted

The **Data tab** contribution (`phoenix_kit_project_extensions/0` +
`Web.ProjectDataLive`) follows the same duck-typed, one-way discovery contract
as the Sites tab in `phoenix_kit_locations#10` — the projects package finds the
function, and this package gains no dependency on projects. Suite repairs and
the sitemap-source test addition are straightforward.

The **`transliterate: true` fixes are real and valuable.** Three call sites
(`Mirror.Importer.generate_slug_if_missing/3`,
`Mirror.Importer.preview_generated_slug/1`, and the data-form slug path) were
calling core's `Slug.slugify/1` without it. Core's option defaults to `false`,
after which the `[^a-z0-9]+` pass deletes every non-ASCII character — so a
Cyrillic or Greek title slugged to `""`. Same class of defect as
`phoenix_kit_document_creator#32`, which this sweep also merged.

## Fixed on `main`: the `locale:` option does nothing

The PR also passes a `locale:` option and adds a comment asserting the
behaviour it buys:

```elixir
# current_lang is the language this title is IN — a German entry wants oe, an
# Estonian one o. It was a parameter here and was being discarded.
|> Slug.slugify(locale: current_lang, transliterate: true)
```

**`PhoenixKit.Utils.Slug.slugify/2` has no `:locale` option.** It reads exactly
two keys — `Keyword.get(opts, :separator, "-")` and
`Keyword.get(opts, :transliterate, false)` — so an unknown `:locale` key is
silently discarded. Core's transliteration is a Cyrillic map plus an NFD
combining-mark strip, which is not locale-sensitive by construction.

Verified empirically against core 2.0.0 rather than by reading:

| Input | no locale | `locale: "de"` | `locale: "et"` |
|---|---|---|---|
| `Schön Wetter` | `schon-wetter` | `schon-wetter` | `schon-wetter` |
| `Õun ja Mänd` | `oun-ja-mand` | `oun-ja-mand` | `oun-ja-mand` |
| `Привет мир` | `privet-mir` | `privet-mir` | `privet-mir` |

German gets `schon`, **not** `schoen`. The option changes nothing, and the
comment documents behaviour the system does not have — the worse half of the
problem, since a future reader would trust it.

This is the same failure mode as the bug the PR is fixing: an option that looks
load-bearing and is silently ignored.

**What I changed on `main`:**
- Dropped `locale:` from both `Slug.slugify/2` call sites; kept `transliterate: true`.
- Rewrote the comment to state what actually happens, and to note that
  `current_lang` still matters where it genuinely does — scoping the uniqueness
  check to the language the slug lives in.
- Reverted `auto_generate_entity_slug/4` to `/3`. The added `lang` parameter fed
  only the dead option (`slug_taken_by_other?/3` never took it), so once the
  option went, the parameter was dead code that `--warnings-as-errors` would
  reject. Updated its three call sites.

Making transliteration genuinely locale-aware would mean changing core's
`Slug.transliterate/1`, which is out of scope for this sweep and would need its
own release.

## Verification

| Check | Result |
|---|---|
| `mix precommit` | **passes** against core 2.0.0, after the fix |
| `mix test` | **420 tests, 0 failures** (612 excluded — no Postgres available) |
